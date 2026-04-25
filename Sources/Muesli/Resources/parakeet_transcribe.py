#!/usr/bin/env python3

import argparse
import contextlib
import io
import json
import sys
import traceback


REQUIRED_MODULES = [
    "torch",
    "torchaudio",
    "nemo.collections.asr",
]


def check_dependencies() -> int:
    missing = []
    for module in REQUIRED_MODULES:
        try:
            __import__(module)
        except ModuleNotFoundError:
            missing.append(module)
        except Exception as error:
            print(
                json.dumps(
                    {
                        "ok": False,
                        "missing": [],
                        "python": sys.executable,
                        "error": f"{module}: {error}",
                    },
                    ensure_ascii=False,
                )
            )
            return 4
        else:
            continue
        if module not in missing:
            missing.append(module)
    payload = {
        "ok": not missing,
        "missing": missing,
        "python": sys.executable,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0 if not missing else 3


class ParakeetWorker:
    def __init__(self) -> None:
        self.models = {}

    def transcribe(self, request: dict) -> dict:
        request_id = request.get("id", "")
        model_name = request.get("model")
        audio = request.get("audio")

        if not model_name:
            return {"id": request_id, "ok": False, "error": "missing model"}
        if not audio:
            return {"id": request_id, "ok": False, "error": "missing audio"}

        try:
            with contextlib.redirect_stdout(sys.stderr):
                model = self._model(model_name)
                output = model.transcribe([audio])

            item = output[0]
            text = getattr(item, "text", str(item))
            return {"id": request_id, "ok": True, "text": text, "model": model_name}
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            return {"id": request_id, "ok": False, "error": str(error), "model": model_name}

    def preload(self, request: dict) -> dict:
        request_id = request.get("id", "")
        model_name = request.get("model")

        if not model_name:
            return {"id": request_id, "ok": False, "error": "missing model"}

        try:
            self._model(model_name)
            return {"id": request_id, "ok": True, "model": model_name}
        except Exception as error:
            traceback.print_exc(file=sys.stderr)
            return {"id": request_id, "ok": False, "error": str(error), "model": model_name}

    def _model(self, model_name: str):
        if model_name not in self.models:
            with contextlib.redirect_stdout(sys.stderr):
                import nemo.collections.asr as nemo_asr

                self.models[model_name] = nemo_asr.models.ASRModel.from_pretrained(model_name=model_name)
        return self.models[model_name]


def run_worker() -> int:
    worker = ParakeetWorker()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            response = {"id": "", "ok": False, "error": f"invalid json: {error}"}
        else:
            if request.get("type") == "shutdown":
                return 0
            if request.get("type") == "preload":
                response = worker.preload(request)
            else:
                response = worker.transcribe(request)

        print(json.dumps(response, ensure_ascii=False), flush=True)

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Transcribe audio with NVIDIA Parakeet through NeMo.")
    parser.add_argument("audio", nargs="?", help="Path to a 16 kHz mono WAV file.")
    parser.add_argument("--model", default="nvidia/parakeet-tdt-0.6b-v3")
    parser.add_argument("--check-dependencies", action="store_true")
    parser.add_argument("--worker", action="store_true")
    args = parser.parse_args()

    if args.check_dependencies:
        return check_dependencies()

    if args.worker:
        return run_worker()

    if not args.audio:
        parser.error("audio is required unless --check-dependencies is used")

    try:
        worker = ParakeetWorker()
        response = worker.transcribe({"id": "cli", "model": args.model, "audio": args.audio})
        if not response.get("ok"):
            print(response.get("error", "unknown error"), file=sys.stderr)
            return 1

        text = response.get("text", "")
        print(json.dumps({"text": text, "model": args.model}, ensure_ascii=False))
        return 0
    except ModuleNotFoundError as error:
        print(
            "Missing Python dependency: "
            f"{error.name}. Run ./script/setup_python.sh or set MUESLI_PYTHON to a prepared environment.",
            file=sys.stderr,
        )
        return 3
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

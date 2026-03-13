"""
CodeProject.AI adapter: image and video description and VQA using Ollama (Ollama MultiModal LLM by OmegaIT). Configurable vision models; supports video via frame sampling and summarization.
Supports images and video (multimodal): for video, samples frames, describes each with the vision model,
then summarizes with a text model. Follows the same pattern as PythonSimple/detect_adapter.py.
Inference runs in the Ollama server process; this module reports GPU capability for the dashboard.
Video description runs synchronously; use conservative OLLAMA_VIDEO_MAX_FRAMES to avoid server timeouts.
Also exposes an OpenAI-compatible chat/completions endpoint for LLM Vision (Home Assistant HACS).
"""
from __future__ import annotations

import base64
import io
import json
import os
import tempfile
import uuid
from pathlib import Path

# CodeProject.AI SDK
from codeproject_ai_sdk import LogMethod, LogVerbosity, RequestData, ModuleOptions, ModuleRunner, JSON

import ollama
from ollama import ResponseError
from PIL import Image

try:
    import cv2
    _HAS_CV2 = True
except ImportError:
    _HAS_CV2 = False

# Config (overridable via env / ModuleOptions)
MAX_IMAGE_SIZE = 1024
VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm"}
VIDEO_SUMMARY_PROMPT = (
    "Summarize what happens in this video in up to three sentences. "
    "Use only the frame descriptions below, no other information."
)


def _image_to_jpeg_bytes(img: Image.Image, max_size: int = MAX_IMAGE_SIZE) -> bytes:
    w, h = img.size
    if w > max_size or h > max_size:
        ratio = min(max_size / w, max_size / h)
        new_size = (int(w * ratio), int(h * ratio))
        img = img.resize(new_size, Image.Resampling.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85)
    return buf.getvalue()


def _load_image_bytes(image_input) -> bytes:
    """Load image from PIL Image, file path, path-like, or bytes."""
    if image_input is None:
        raise ValueError("No image provided")
    if isinstance(image_input, Image.Image):
        return _image_to_jpeg_bytes(image_input)
    if isinstance(image_input, bytes):
        img = Image.open(io.BytesIO(image_input)).convert("RGB")
        return _image_to_jpeg_bytes(img)
    path = Path(str(image_input))
    if not path.exists():
        raise FileNotFoundError(f"Image file not found: {path}")
    img = Image.open(path).convert("RGB")
    return _image_to_jpeg_bytes(img)


def _extract_frames(
    path: Path,
    interval_sec: float,
    max_frames: int,
    max_size: int = MAX_IMAGE_SIZE,
) -> list[tuple[float, bytes]]:
    """Extract sampled frames from a video file as JPEG bytes. Returns list of (timestamp_sec, bytes)."""
    if not _HAS_CV2:
        raise RuntimeError("OpenCV (cv2) is required for video support. Install opencv-python.")
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {path}")
    fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    interval_frames = max(1, int(fps * interval_sec))
    result: list[tuple[float, bytes]] = []
    frame_index = 0
    while frame_index < total_frames and len(result) < max_frames:
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ret, frame = cap.read()
        if not ret:
            break
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        img = Image.fromarray(rgb)
        result.append((frame_index / fps, _image_to_jpeg_bytes(img, max_size)))
        frame_index += interval_frames
    cap.release()
    return result


def _is_video_bytes(data: bytes, path_or_suffix: str | Path | None) -> bool:
    """Heuristic: try opening as video (temp file) or use extension."""
    if path_or_suffix:
        s = Path(str(path_or_suffix)).suffix.lower()
        if s in VIDEO_EXTENSIONS:
            return True
    if not _HAS_CV2 or not data:
        return False
    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as f:
        try:
            f.write(data)
            f.flush()
            f.close()
            cap = cv2.VideoCapture(f.name)
            ok = cap.isOpened() and (cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0) > 0
            cap.release()
            return ok
        finally:
            try:
                os.unlink(f.name)
            except Exception:
                pass
    return False


def _parse_openai_messages(messages: list) -> tuple[bytes | None, str]:
    """Extract first image (base64) and combined text prompt from OpenAI-format messages. Returns (image_bytes, prompt)."""
    prompt_parts: list[str] = []
    image_bytes: bytes | None = None
    for msg in messages or []:
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            prompt_parts.append(content)
            continue
        if isinstance(content, list):
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "text":
                    prompt_parts.append((part.get("text") or "").strip())
                elif part.get("type") == "image_url":
                    url = part.get("image_url")
                    url_str = url.get("url") if isinstance(url, dict) else str(url)
                    if url_str.startswith("data:") and ";base64," in url_str:
                        b64 = url_str.split(";base64,", 1)[-1]
                        try:
                            image_bytes = base64.b64decode(b64)
                            break
                        except Exception:
                            pass
    prompt = " ".join(prompt_parts).strip() or "Describe this image in a few sentences."
    return image_bytes, prompt


def _safe_repr(val, max_len: int = 200) -> str:
    """Return a short safe repr for logging (no huge base64)."""
    if val is None:
        return "None"
    if isinstance(val, bytes):
        return f"<bytes len={len(val)}>"
    if isinstance(val, str):
        if "base64" in val.lower() or len(val) > max_len:
            return f"<str len={len(val)} prefix={repr(val[:80])!s}>"
        return repr(val)[:max_len]
    if isinstance(val, (list, dict)):
        return f"<{type(val).__name__} len={len(val)}>"
    return repr(val)[:max_len]


def _log_request_data(data: RequestData, prefix: str = "chat-completions request") -> None:
    """Log a summary of RequestData to CodeProject.AI module log (info level)."""
    lines = [f"[OmegaOllama] {prefix}:"]
    keys_to_try = (
        "model", "messages", "body", "request", "payload", "requestBody",
        "content", "data", "json", "raw", "input", "prompt",
    )
    for key in keys_to_try:
        try:
            v = data.get_value(key)
            if v is not None:
                lines.append(f"  get_value({key!r}) = {_safe_repr(v)}")
        except Exception as e:
            lines.append(f"  get_value({key!r}) raised {e!r}")
    values_dict = getattr(data, "values", None)
    if isinstance(values_dict, dict):
        lines.append(f"  data.values keys: {list(values_dict.keys())!r}")
        for k, v in values_dict.items():
            lines.append(f"    values[{k!r}] = {_safe_repr(v)}")
    attrs = [a for a in dir(data) if not a.startswith("_")]
    lines.append(f"  RequestData public attrs: {attrs!r}")
    msg = "\n".join(lines)
    print(msg)


def _openai_choices_response(content: str, model: str, finish_reason: str = "stop") -> JSON:
    """Build OpenAI chat completions-style response for LLM Vision. Includes success for CodeProject.AI."""
    return {
        "success": True,
        "id": f"chatcmpl-{uuid.uuid4().hex[:24]}",
        "object": "chat.completion",
        "choices": [
            {
                "message": {"role": "assistant", "content": content},
                "finish_reason": finish_reason,
                "index": 0,
            }
        ],
        "model": model,
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


class OmegaOllamaMultiModalLLMAdapter(ModuleRunner):
    """Adapter for Ollama MultiModal: describe image or video, or answer prompt. By OmegaIT LLC.
    Inference runs in the Ollama server (separate process); GPU is used by Ollama when available.
    We report GPU capability so the dashboard Enable/Disable GPU button and status work correctly.
    """

    def initialise(self):
        self.model_name = ModuleOptions.getEnvVariable("OLLAMA_VISION_MODEL", "moondream")
        # Default: use same model for video summary (no second model needed). Override with OLLAMA_SUMMARY_MODEL if desired.
        self.summary_model = ModuleOptions.getEnvVariable("OLLAMA_SUMMARY_MODEL", "").strip() or self.model_name
        # Keep defaults low so describe-video finishes within typical server request timeout (~60–120s)
        self.video_interval_sec = float(ModuleOptions.getEnvVariable("OLLAMA_VIDEO_INTERVAL_SEC", "5"))
        self.video_max_frames = int(ModuleOptions.getEnvVariable("OLLAMA_VIDEO_MAX_FRAMES", "6"))
        self._num_descriptions = 0
        self._num_errors = 0

        # GPU: Ollama runs in its own process and uses GPU when available. We report capability
        # so the dashboard Enable/Disable GPU button works. Use PyTorch CUDA if present (like
        # PythonSimple), otherwise fall back to system NVIDIA GPU check (nvidia-smi) so we don't
        # require PyTorch in this module.
        if self.enable_GPU:
            if self.system_info.hasTorchCuda:
                self.can_use_GPU = True
                self.inference_device = "GPU"
                self.inference_library = "CUDA"
            elif self.system_info.hasNvidiaGPU:
                self.can_use_GPU = True
                self.inference_device = "GPU"
                self.inference_library = "CUDA"
        else:
            self.can_use_GPU = False
            self.inference_device = "CPU"
            self.inference_library = ""

    def process(self, data: RequestData) -> JSON:
        cmd = (data.command or "").strip().lower()
        if cmd not in ("describe-image", "describe-video", "chat-completions"):
            self.report_error(None, __file__, f"Unknown command {data.command}")
            return {"success": False, "error": f"Unknown command {data.command}. Use describe-image, describe-video, or chat-completions.", "description": ""}

        # OpenAI-compatible endpoint for LLM Vision (Home Assistant): JSON body with messages + optional model
        if cmd == "chat-completions":
            try:
                return self._process_chat_completions(data)
            except Exception as e:
                return _openai_choices_response(
                    f"Error processing request: {e}",
                    (data.get_value("model") or "omega-ollama").strip() or "omega-ollama",
                )

        try:
            prompt = data.get_value("prompt") or "Describe this image in a few sentences."
            if hasattr(prompt, "strip"):
                prompt = prompt.strip() or "Describe this image in a few sentences."

            if cmd == "describe-image":
                # Image-only: first file (Explorer sends as "image")
                image_input = data.get_image(0)
                if image_input is None:
                    image_input = data.get_file_bytes(0)
                if image_input is None:
                    return {"success": False, "error": "No image file provided. Use the describe-image endpoint with an image file.", "description": ""}

                file_bytes, path_for_ext = None, None
                if isinstance(image_input, Image.Image):
                    file_bytes = _image_to_jpeg_bytes(image_input)
                    is_video = False
                elif isinstance(image_input, bytes):
                    file_bytes = image_input
                    path_for_ext = None
                    try:
                        Image.open(io.BytesIO(file_bytes)).verify()
                        is_video = False
                    except Exception:
                        is_video = _HAS_CV2 and _is_video_bytes(file_bytes, None)
                else:
                    path = Path(str(image_input))
                    if not path.exists():
                        return {"success": False, "error": f"File not found: {path}", "description": ""}
                    path_for_ext = path
                    file_bytes = path.read_bytes()
                    is_video = path.suffix.lower() in VIDEO_EXTENSIONS or _is_video_bytes(file_bytes, path)

                if is_video:
                    return {"success": False, "error": "Video file provided. Use the describe-video endpoint for video files.", "description": ""}

                if path_for_ext is not None:
                    image_bytes = _load_image_bytes(path_for_ext)
                else:
                    image_bytes = _load_image_bytes(image_input)
                return self._process_single_image(image_bytes, prompt)
            else:
                # describe-video: synchronous (server does not handle long-running response without throwing)
                video_input = data.get_file_bytes(0)
                if video_input is None:
                    path = data.get_value("video") if hasattr(data, "get_value") else None
                    if path is None and hasattr(data, "files") and data.files and len(data.files) > 0:
                        fd = data.files[0]
                        path = fd.get("filename") or fd.get("path")
                    if path is not None:
                        path = Path(str(path))
                        if path.exists():
                            return self._process_video(path, prompt)
                    return {"success": False, "error": "No video file provided. Use the describe-video endpoint with a video file.", "description": ""}
                try:
                    Image.open(io.BytesIO(video_input)).verify()
                    return {"success": False, "error": "Image file provided. Use the describe-image endpoint for image files.", "description": ""}
                except Exception:
                    pass
                if not _HAS_CV2:
                    return {"success": False, "error": "OpenCV (cv2) is required for video support.", "description": ""}
                with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tf:
                    try:
                        tf.write(video_input)
                        tf.flush()
                        tf.close()
                        return self._process_video(Path(tf.name), prompt)
                    finally:
                        try:
                            os.unlink(tf.name)
                        except Exception:
                            pass
        except Exception as e:
            return {"success": False, "error": str(e), "description": ""}

    def _process_single_image(self, image_bytes: bytes, prompt: str) -> JSON:
        """Run vision model on a single image and return result."""
        try:
            response = ollama.chat(
                model=self.model_name,
                messages=[
                    {"role": "user", "content": prompt, "images": [image_bytes]},
                ],
            )
            content = (response.get("message") or {}).get("content") or ""
            return {"success": True, "description": content.strip(), "error": ""}
        except ResponseError as e:
            return {"success": False, "error": str(e), "description": ""}
        except Exception as e:
            return {"success": False, "error": str(e), "description": ""}

    def _process_chat_completions(self, data: RequestData) -> JSON:
        """Handle OpenAI-format chat/completions request (for LLM Vision). Returns OpenAI-style JSON."""
        _log_request_data(data, "chat-completions request (full dump)")
        model = (data.get_value("model") or "omega-ollama").strip() or "omega-ollama"
        messages = data.get_value("messages")
        # CodeProject.AI may pass JSON body as key-value (messages, model) or as single body/request string
        body_keys = (
            "body", "request", "payload", "requestBody", "content", "data", "json", "raw", "input"
        )
        if messages is None:
            for key in body_keys:
                body = data.get_value(key)
                if body is None:
                    continue
                if isinstance(body, str) and (body.strip().startswith("{") or body.strip().startswith("[")):
                    try:
                        body = json.loads(body)
                    except json.JSONDecodeError:
                        continue
                if isinstance(body, dict):
                    messages = body.get("messages")
                    if body.get("model"):
                        model = body.get("model", model)
                    if messages is not None:
                        break
        # If RequestData has a .values dict (or similar), scan for any JSON-like value containing "messages"
        values_dict = getattr(data, "values", None)
        if messages is None and isinstance(values_dict, dict):
            for _k, v in values_dict.items():
                if isinstance(v, str) and ("messages" in v or "image_url" in v):
                    try:
                        parsed = json.loads(v)
                        if isinstance(parsed, dict) and "messages" in parsed:
                            messages = parsed.get("messages")
                            break
                    except json.JSONDecodeError:
                        pass
                elif isinstance(v, list) and v and isinstance(v[0], dict) and "content" in str(v[0]):
                    messages = v
                    break
        if isinstance(messages, str):
            try:
                messages = json.loads(messages)
            except json.JSONDecodeError:
                messages = None
        image_bytes, prompt = _parse_openai_messages(messages if isinstance(messages, list) else [])
        # Fallback: server may have converted JSON to form data (image file + prompt)
        if not image_bytes:
            image_input = data.get_image(0) if hasattr(data, "get_image") else None
            if image_input is None and hasattr(data, "get_file_bytes"):
                image_input = data.get_file_bytes(0)
            if image_input is not None:
                try:
                    if isinstance(image_input, bytes):
                        image_bytes = _load_image_bytes(image_input)
                    else:
                        image_bytes = _load_image_bytes(image_input)
                    prompt = (data.get_value("prompt") or prompt or "Describe this image.").strip()
                except Exception:
                    image_bytes = None
        if not image_bytes:
            return _openai_choices_response(
                "No image provided. Send a message with an image (image_url) for vision.",
                model,
            )
        result = self._process_single_image(image_bytes, prompt)
        if result.get("success"):
            return _openai_choices_response(result.get("description", ""), model)
        return _openai_choices_response(
            result.get("error") or "Vision request failed.",
            model,
        )

    def _process_video(self, video_path: Path, prompt: str) -> JSON:
        """Sample frames, describe each with vision model, then summarize with text model."""
        try:
            frames = _extract_frames(
                video_path,
                self.video_interval_sec,
                self.video_max_frames,
                MAX_IMAGE_SIZE,
            )
        except Exception as e:
            return {"success": False, "error": str(e), "description": ""}
        if not frames:
            return {"success": False, "error": "No frames extracted from video", "description": ""}

        frame_descriptions: list[str] = []
        for time_sec, image_bytes in frames:
            try:
                response = ollama.chat(
                    model=self.model_name,
                    messages=[
                        {"role": "user", "content": prompt, "images": [image_bytes]},
                    ],
                )
                content = (response.get("message") or {}).get("content") or ""
                if content:
                    frame_descriptions.append(f"[{time_sec:.1f}s] {content.strip()}")
            except ResponseError:
                pass
        if not frame_descriptions:
            return {"success": False, "error": "No frame descriptions from vision model", "description": ""}

        combined = "\n".join(frame_descriptions)
        summary_prompt = f"These are descriptions of successive video frames:\n\n{combined}\n\n{VIDEO_SUMMARY_PROMPT}"
        try:
            summary_response = ollama.chat(
                model=self.summary_model,
                messages=[{"role": "user", "content": summary_prompt}],
            )
            summary = (summary_response.get("message") or {}).get("content") or ""
            return {"success": True, "description": summary.strip(), "error": ""}
        except ResponseError as e:
            return {"success": False, "error": str(e), "description": ""}
        except Exception as e:
            return {"success": False, "error": str(e), "description": ""}

    def status(self) -> JSON:
        status_data = super().status()
        status_data["numDescriptions"] = self._num_descriptions
        status_data["numErrors"] = self._num_errors
        # Optional: report whether Ollama is using GPU (from Ollama's /api/ps)
        try:
            client = ollama.Client()
            ps = client.ps()
            if ps and hasattr(ps, "models") and ps.models:
                gpu_in_use = any(
                    (getattr(m, "size_vram", 0) or 0) > 0
                    for m in ps.models
                )
                status_data["ollamaGpuInUse"] = gpu_in_use
        except Exception:
            pass
        return status_data

    def update_statistics(self, response):
        super().update_statistics(response)
        if not isinstance(response, dict):
            return
        if response.get("success"):
            self._num_descriptions += 1
        else:
            self._num_errors += 1

    def selftest(self) -> JSON:
        # Use a minimal in-memory image (1x1 pixel) so we don't depend on a test file
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            try:
                Image.new("RGB", (1, 1), (0, 0, 0)).save(f, format="JPEG", quality=85)
                f.flush()
                f.close()
                request_data = RequestData()
                request_data.queue = self.queue_name
                request_data.command = "describe-image"
                request_data.add_file(f.name)
                request_data.add_value("prompt", "Describe this image in one word.")
                result = self.process(request_data)
                success = result.get("success", False)
                msg = "OmegaOllamaMultiModal LLM describe test successful" if success else (result.get("error") or "Self-test failed")
                if self.log_verbosity == LogVerbosity.Loud:
                    print(f"Info: Self-test for {self.module_id}. Success: {success}")
                return {"success": success, "message": msg}
            finally:
                try:
                    os.unlink(f.name)
                except Exception:
                    pass


if __name__ == "__main__":
    OmegaOllamaMultiModalLLMAdapter().start_loop()

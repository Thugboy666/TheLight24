import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def start_api():
    subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "api.server:app", "--host", "0.0.0.0", "--port", "8080"],
        cwd=str(ROOT),
    )

def main():
    if len(sys.argv) < 2:
        print("Usage: python -m cli.lightctl [start]")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "start":
        start_api()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

if __name__ == "__main__":
    main()

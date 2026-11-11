"""Record actual hosted capacity; no 60-GiB disk assumption or global cleanup."""
import argparse, json, os, pathlib, shutil, sys
p = argparse.ArgumentParser()
p.add_argument("--minimum-free-gib", type=float, default=4)
p.add_argument("--output", required=True)
a = p.parse_args()
spaces = {str(x.resolve()): shutil.disk_usage(x)._asdict() for x in [pathlib.Path("."), pathlib.Path("/tmp")]}
ready = min(x["free"] for x in spaces.values()) >= a.minimum_free_gib * 1024**3
data = {"cpu": os.cpu_count(), "memoryKiB": next(x.split()[1] for x in pathlib.Path("/proc/meminfo").read_text().splitlines() if x.startswith("MemTotal:")),
        "disks": spaces, "kvmUsable": os.access("/dev/kvm", os.R_OK | os.W_OK),
        "status": "READY_FOR_ATTEMPT" if ready else "INFRASTRUCTURE_BLOCKED", "minimumFreeGiB": a.minimum_free_gib}
out = pathlib.Path(a.output); out.parent.mkdir(parents=True, exist_ok=True); out.write_text(json.dumps(data, indent=2)+"\n")
print(json.dumps(data))
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f: f.write("Resource status: **"+data["status"]+"**; no build/E2E pass implied.\n")
sys.exit(0 if ready else 78)

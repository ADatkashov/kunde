"""Skip only unchanged native inputs on PR synchronize; unknown metadata runs full checks."""
import json, os, pathlib, re, subprocess
run=True; files=[]
before=os.environ.get("BEFORE_SHA",""); head=os.environ.get("HEAD_SHA","")
if os.environ.get("GITHUB_EVENT_NAME")=="pull_request" and os.environ.get("EVENT_ACTION")=="synchronize":
    if re.fullmatch("[0-9a-f]{40}",before) and re.fullmatch("[0-9a-f]{40}",head):
        files=subprocess.check_output(["git","diff","--name-only",before,head],text=True).splitlines()
        relevant={"scripts/ci/android_graph.init.gradle","scripts/ci/inspect_apk_dependencies.py",
                  "scripts/ci/osv_audit.py","scripts/ci/runner_resources.py","scripts/ci/native_changes.py",
                  ".github/workflows/android-apk.yml"}
        run=any(p.startswith("mobile/") or p in relevant for p in files)
with open(os.environ["GITHUB_OUTPUT"],"a") as out: out.write("run="+str(run).lower()+"\n")
print(json.dumps({"nativeInputsChanged":run,"files":files,"status":"VERIFY_NATIVE" if run else "UNCHANGED_NATIVE_INPUTS_NOT_RETESTED"}))

"""Resolve exactly the two reviewed Dockerfile bases, including pinned digests."""
import datetime,hashlib,json,pathlib,re
from registry_metadata import resolve
source=pathlib.Path("backend/Dockerfile").read_bytes()
bases=re.findall(r"(?im)^FROM\s+(\S+)",source.decode())
assert len(bases)==2
pathlib.Path("reports").mkdir(exist_ok=True)
pathlib.Path("reports/images.json").write_text(json.dumps({"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"dockerfileSha256":hashlib.sha256(source).hexdigest(),"images":[resolve(x) for x in reversed(bases)],"coverage":"immutable base metadata only"},indent=2)+"\n")

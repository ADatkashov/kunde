"""Debug APK DEX-prefix corroboration, not proof against shading/obfuscation."""
import json, pathlib, zipfile
file=pathlib.Path("mobile/build/app/outputs/flutter-apk/app-debug.apk")
prefixes={"bouncycastle":b"Lorg/bouncycastle/","guava":b"Lcom/google/common/",
          "commons-lang3":b"Lorg/apache/commons/lang3/","jose4j":b"Lorg/jose4j/","jdom2":b"Lorg/jdom2/"}
with zipfile.ZipFile(file) as apk:
    dex=[apk.read(name) for name in apk.namelist() if name.endswith(".dex")]
result={name:any(prefix in data for data in dex) for name,prefix in prefixes.items()}
pathlib.Path("reports/apk-package-presence.json").write_text(json.dumps({
    "debugApkDexPackagePrefixes":result,
    "limitations":["No release/shaded-code absence guarantee","Use runtime-classpath graph for ownership"]},indent=2)+"\n")
print("APK_PACKAGE_PRESENCE",json.dumps(result))

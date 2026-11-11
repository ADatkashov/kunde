"""Read official Maven/Android version metadata and Boot BOM; no dependency override is inferred."""
import json, pathlib, urllib.request, xml.etree.ElementTree as ET
out=pathlib.Path("reports"); out.mkdir(exist_ok=True)
urls={
 "boot409":"https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-dependencies/4.0.9/spring-boot-dependencies-4.0.9.pom",
 "agp":"https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml",
 "bcpkix":"https://repo.maven.apache.org/maven2/org/bouncycastle/bcpkix-jdk18on/maven-metadata.xml",
 "bcutil":"https://repo.maven.apache.org/maven2/org/bouncycastle/bcutil-jdk18on/maven-metadata.xml",
 "bcprov":"https://repo.maven.apache.org/maven2/org/bouncycastle/bcprov-jdk18on/maven-metadata.xml",
 "guava":"https://repo.maven.apache.org/maven2/com/google/guava/guava/maven-metadata.xml",
 "lang":"https://repo.maven.apache.org/maven2/org/apache/commons/commons-lang3/maven-metadata.xml",
 "jose":"https://repo.maven.apache.org/maven2/org/bitbucket/b_c/jose4j/maven-metadata.xml",
 "jdom":"https://repo.maven.apache.org/maven2/org/jdom/jdom2/maven-metadata.xml"}
report={}
for name,url in urls.items():
    with urllib.request.urlopen(url,timeout=30) as r: data=r.read()
    (out/(name+".xml")).write_bytes(data)
    root=ET.fromstring(data)
    if name=="boot409":
        props=root.find("{*}properties")
        report[name]={x.tag.split("}")[-1]:x.text for x in props if any(v in x.tag for v in ["spring-framework.version","spring-security.version","flyway.version","jackson","tomcat.version","postgresql.version"])}
    else:
        versions=[x.text for x in root.findall("./versioning/versions/version")]
        report[name]=[x for x in versions if x.startswith("9.1.")] if name=="agp" else versions[-12:]
(out/"vendor-versions.json").write_text(json.dumps(report,indent=2)+"\n")
print("VENDOR_EVIDENCE",json.dumps(report))

"""Verify each selected maintenance artifact exists in official Maven Central before Gradle."""
import urllib.request
coordinates=[("org.bouncycastle","bcprov-jdk18on","1.85.2"),("org.bouncycastle","bcpkix-jdk18on","1.85"),
    ("org.bouncycastle","bcutil-jdk18on","1.85"),("com.google.guava","guava","33.7.2-jre"),
    ("org.apache.commons","commons-lang3","3.18.0"),("org.bitbucket.b_c","jose4j","0.9.6"),("org.jdom","jdom2","2.0.6.1")]
for group,name,version in coordinates:
    url="https://repo.maven.apache.org/maven2/"+group.replace(".","/")+"/"+name+"/"+version+"/"+name+"-"+version+".pom"
    with urllib.request.urlopen(urllib.request.Request(url,method="HEAD"),timeout=20) as r:
        assert r.status==200
        print("VERIFIED_NATIVE_ARTIFACT",group+":"+name+":"+version,r.status)

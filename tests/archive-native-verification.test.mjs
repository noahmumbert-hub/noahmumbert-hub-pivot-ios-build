import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../public/PIVOT-iOS/", import.meta.url));
const read = path => readFileSync(join(root, path), "utf8");
function helper(name, args) {
  return spawnSync("/bin/zsh", ["-c", 'plist_read() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }; source "$1"; shift; task="$1"; shift; "$task" "$@"', "test", join(root,"Scripts/refresher-verification.sh"), name, ...args], {encoding:"utf8"});
}
test("phone readback handles app arrays and supported Xcode key variants", () => {
  const dir=mkdtempSync(join(tmpdir(), "pivot-verification-test-"));
  try {
    const file=join(dir,"apps.json");
    for (const row of [
      {bundleIdentifier:"com.noahmumbert.PIVOT",bundleVersionNumber:"100.2.3"},
      {bundleID:"com.noahmumbert.PIVOT",bundleVersion:"100.2.3"},
    ]) {
      writeFileSync(file,JSON.stringify({info:{outcome:"success"},result:{apps:[{bundleIdentifier:"other",bundleVersionNumber:"1"},row]}}));
      const result=helper("pivot_reported_build",[file,"com.noahmumbert.PIVOT"]);
      assert.equal(result.status,0,result.stderr);
      assert.equal(result.stdout.trim(),"100.2.3");
    }
    for (const json of [{info:{outcome:"success"},result:{apps:[]}}, {info:{outcome:"failure"},result:{apps:[{bundleIdentifier:"com.noahmumbert.PIVOT",bundleVersionNumber:"100.2.3"}]}}]) {
      writeFileSync(file,JSON.stringify(json));
      assert.equal(helper("pivot_reported_build",[file,"com.noahmumbert.PIVOT"]).status,1);
    }
  } finally {rmSync(dir,{recursive:true,force:true});}
});
test("a download, stale receipt, different phone or different source cannot pass installation verification", () => {
  const dir=mkdtempSync(join(tmpdir(),"pivot-receipt-test-"));
  try {
    const file=join(dir,"state.json");
    const valid={NeedsSourceInstall:false,PendingInstall:false,InstalledSourceFingerprint:"abc",InstalledReleaseID:"2026.09.26.2",VerifiedDeviceUDID:"phone-a",InstalledBuildVersion:"100.2.3",LastVerifiedEpoch:2000};
    const check=patch=>{
      writeFileSync(file,JSON.stringify({...valid,...patch}));
      return helper("pivot_state_is_verified",[file,"abc","2026.09.26.2","phone-a","1999"]).status;
    };
    assert.equal(check({}),0);
    for (const patch of [{NeedsSourceInstall:true},{PendingInstall:true},{InstalledSourceFingerprint:"old"},{InstalledReleaseID:"old"},{VerifiedDeviceUDID:"brian"},{InstalledBuildVersion:""},{LastVerifiedEpoch:1998},{LastVerifiedEpoch:null}]) assert.equal(check(patch),1,JSON.stringify(patch));
  } finally {rmSync(dir,{recursive:true,force:true});}
});

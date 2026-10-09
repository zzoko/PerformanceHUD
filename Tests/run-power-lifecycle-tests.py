#!/usr/bin/env python3
"""Exercise sampler startup/streaming and optionally current-user launchd cleanup."""
from pathlib import Path
import argparse, concurrent.futures, json, os, plistlib, signal, subprocess, tempfile, time, uuid
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
launchd = parser.add_mutually_exclusive_group()
launchd.add_argument('--skip-launchd', dest='include_launchd', action='store_false',
                     help='run the unprivileged sampler cases without registering a launchd job')
launchd.add_argument('--include-launchd', dest='include_launchd', action='store_true',
                     help='also test a disposable current-user launchd job (standalone default)')
parser.set_defaults(include_launchd=True)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='PerformanceHUD-power-lifecycle-') as folder:
    out = Path(folder); binary=out/'tests'
    subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',
        str(ROOT/'PowerHelperShared/PowerHelperProtocol.swift'),str(ROOT/'PowerHelper/PowerSampler.swift'),
        str(ROOT/'PowerHelper/PowerSamplerChild.swift'),str(ROOT/'PerformanceHUD/PowerHelperState.swift'),
        str(ROOT/'Tests/PowerSamplerLifecycleTests.swift'),'-o',str(binary)],check=True)
    def case(name):
        p=subprocess.run([str(binary),name],capture_output=True,text=True,timeout=25)
        if p.returncode: raise RuntimeError(name+'\n'+p.stdout+p.stderr)
        return p.stdout.strip()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(case,['continuous','slow-start','startup-hung','stream-hung','empty-exit']): print(result,flush=True)
    if args.include_launchd:
        label='andrei.PerformanceHUD.CleanupTest.'+uuid.uuid4().hex
        domain='gui/'+str(os.getuid()); target=domain+'/'+label
        plist=out/'cleanup.plist'; state=out/'pids.json'
        plist.write_bytes(plistlib.dumps({'Label':label,'ProgramArguments':[str(binary),'--job',str(state)],
            'RunAtLoad':True,'AbandonProcessGroup':False}))
        registered=False
        try:
            subprocess.run(['launchctl','bootstrap',domain,str(plist)],check=True,capture_output=True)
            registered=True
            deadline=time.monotonic()+8
            while not state.exists() and time.monotonic()<deadline: time.sleep(.1)
            data=json.loads(state.read_text())
            assert data['parentGroup']==data['parent']==data['childGroup'],data
            os.kill(data['parent'],signal.SIGKILL)
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                try: os.kill(data['child'],0)
                except ProcessLookupError: break
                time.sleep(.1)
            else: raise AssertionError('launchd did not remove child after parent SIGKILL')
            print('PASS launchd cleanup: abrupt parent death reaps joined child without pipe writes',flush=True)
        finally:
            if registered:
                subprocess.run(['launchctl','bootout',target],capture_output=True)
    else:
        print('SKIP launchd cleanup: no job registered (--skip-launchd)',flush=True)

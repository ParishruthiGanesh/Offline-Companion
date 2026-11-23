#!/usr/bin/env python3
"""Compile the actual platform-independent production models/router with Swift on a Mac."""
from pathlib import Path
import shutil,subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1]
compiler=shutil.which('swiftc')
if not compiler:
    print('Swift compiler unavailable here. Run this script on the Mac with Xcode installed.',file=sys.stderr)
    sys.exit(2)
app=root/'OfflineCompanion'
models=(app/'OfflineMapView.swift').read_text()
models=models[models.index('struct MapPoint:'):models.index('struct CountryOutline:')]
places=(app/'LocationView.swift').read_text()
places=places[places.index('struct MeetingPoint:'):places.index('@MainActor')]
with tempfile.TemporaryDirectory(prefix='offline-core-tests-') as temp:
    temp=Path(temp)
    (temp/'Models.swift').write_text('import Foundation\n'+models+'\n'+places)
    (temp/'main.swift').write_text((root/'DeveloperNotes/CoreTests.swift').read_text())
    output=temp/'core-tests'
    subprocess.run([compiler,'-swift-version','5',str(temp/'Models.swift'),str(app/'OfflineWalkingRouter.swift'),
                    str(app/'SharedLocationPacket.swift'),str(temp/'main.swift'),'-o',str(output)],check=True)
    subprocess.run([str(output)],check=True)

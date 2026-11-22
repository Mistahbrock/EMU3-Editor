#!/bin/bash
set -e
cd "$(dirname "$0")/.."
mkdir -p build
python3 -I Tests/make_test_bank.py build/test.e4b
clang -fobjc-arc -Wall -ISources/Model Sources/Model/EDBank.m Sources/Model/NSData+EDWrite.m Sources/Model/EDLegacyBank.m Tests/ModelSelfTest.m -framework Foundation -framework AudioToolbox -o build/modeltest
build/modeltest build/test.e4b
clang -fobjc-arc -Wall -ISources/Model -ISources/MIDI Sources/MIDI/EDSDS.m Sources/Model/EDBank.m Sources/Model/NSData+EDWrite.m Sources/Model/EDLegacyBank.m Tests/SDSTest.m -framework Foundation -framework AudioToolbox -o build/sdstest
build/sdstest
clang -fobjc-arc -Wall -ISources/Model -ISources/MIDI Sources/MIDI/EDSMDI.m Sources/MIDI/EDSDS.m Sources/Model/EDBank.m Sources/Model/NSData+EDWrite.m Sources/Model/EDLegacyBank.m Tests/SMDITest.m -framework Foundation -framework AudioToolbox -o build/smditest
build/smditest
clang -fobjc-arc -Wall -ISources/Model Sources/Model/EDBank.m Sources/Model/NSData+EDWrite.m Sources/Model/EDLegacyBank.m Sources/Model/EDPreset+Params.m Tests/NewPresetTest.m -framework Foundation -framework AudioToolbox -o build/newpresettest
build/newpresettest build/test.e4b
[ -f build/real.e4b ] && build/newpresettest build/real.e4b
clang -fobjc-arc -Wall -ISources/Model Sources/Model/EDBank.m Sources/Model/NSData+EDWrite.m Sources/Model/EDLegacyBank.m Sources/Model/EDPreset+Params.m Tests/EraseTest.m -framework Foundation -framework AudioToolbox -o build/erasetest
build/erasetest build/test.e4b
[ -f build/real.e4b ] && build/erasetest build/real.e4b
true

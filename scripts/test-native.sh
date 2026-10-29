#!/usr/bin/env bash
set -euo pipefail
compiler="${RUNNER_TEMP:-/tmp}/motorista-kotlin"
mkdir -p "$compiler"
curl -fsSL --retry 3 https://github.com/JetBrains/kotlin/releases/download/v2.1.20/kotlin-compiler-2.1.20.zip -o "$compiler/compiler.zip"
echo "a118197b0de55ffab2bc8d5cd03a5e39033cfb53383d6931bc761dec0784891a  $compiler/compiler.zip" | sha256sum -c -
unzip -q -o "$compiler/compiler.zip" -d "$compiler"
source=android/app/src/main/kotlin/com/motoristapro/app
"$compiler/kotlinc/bin/kotlinc" "$source/RideReceiptParser.kt" "$source/ScreenOfferParser.kt" "$source/RideLedger.kt" "$source/RouteRisk.kt" test/native/RideRegression.kt -include-runtime -d "$compiler/ride-tests.jar"
java -jar "$compiler/ride-tests.jar"

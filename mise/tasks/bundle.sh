#!/usr/bin/env bash
set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}▶ $1${NC}"
}

# Configuration
CERTIFICATE_NAME="Developer ID Application: Tuist GmbH (U6LC622NKF)"
APPLE_ID="pedro@pepicrft.me"
TEAM_ID='U6LC622NKF'
TMP_DIR=/private$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Setup keychain for signing (CI only)
if [ "${CI:-}" = "true" ]; then
    print_status "Setting up Keychain for signing..."
    KEYCHAIN_PATH=$TMP_DIR/keychain.keychain
    KEYCHAIN_PASSWORD=$(uuidgen)

    security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
    security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
    security default-keychain -s $KEYCHAIN_PATH
    security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH

    echo $BASE_64_DEVELOPER_ID_APPLICATION_CERTIFICATE | base64 --decode > $TMP_DIR/certificate.p12
    security import $TMP_DIR/certificate.p12 -P $CERTIFICATE_PASSWORD -A
fi

# Build the Cassiopeia dynamic library
print_status "Building Cassiopeia dynamic library..."
swift build -c release --product Cassiopeia

# Create build directory
mkdir -p build

# Find the built dylib and copy it to build/
DYLIB_PATH=$(swift build -c release --product Cassiopeia --show-bin-path)/libCassiopeia.dylib

if [ -f "$DYLIB_PATH" ]; then
    cp "$DYLIB_PATH" build/libCassiopeia.dylib
    print_status "Dynamic library created at build/libCassiopeia.dylib"
else
    echo -e "${RED}✗ Failed to find built dylib at $DYLIB_PATH${NC}"
    exit 1
fi

# Sign the dylib
if [ "${CI:-}" = "true" ]; then
    print_status "Signing dylib..."
    /usr/bin/codesign --sign "$CERTIFICATE_NAME" --timestamp --options runtime --verbose build/libCassiopeia.dylib

    # Notarize
    print_status "Notarizing dylib..."
    cd build
    zip -q -r "notarization-bundle.zip" libCassiopeia.dylib

    RAW_JSON=$(xcrun notarytool submit "notarization-bundle.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --output-format json)
    echo "$RAW_JSON"
    SUBMISSION_ID=$(echo "$RAW_JSON" | jq -r '.id')
    echo "Submission ID: $SUBMISSION_ID"

    while true; do
        STATUS=$(xcrun notarytool info "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_SPECIFIC_PASSWORD" \
            --output-format json | jq -r '.status')

        case $STATUS in
            "Accepted")
                echo -e "${GREEN}Notarization succeeded!${NC}"
                break
                ;;
            "In Progress")
                echo "Notarization in progress... waiting 30 seconds"
                sleep 30
                ;;
            "Invalid"|"Rejected")
                echo "Notarization failed with status: $STATUS"
                xcrun notarytool log "$SUBMISSION_ID" \
                    --apple-id "$APPLE_ID" \
                    --team-id "$TEAM_ID" \
                    --password "$APP_SPECIFIC_PASSWORD"
                exit 1
                ;;
            *)
                echo "Unknown status: $STATUS"
                exit 1
                ;;
        esac
    done
    rm "notarization-bundle.zip"
    cd ..
fi

# Create final bundle
print_status "Creating libCassiopeia.tar.gz..."
cd build
tar -czf libCassiopeia.tar.gz libCassiopeia.dylib

print_status "✓ Bundle created at build/libCassiopeia.tar.gz"
#!/usr/bin/env bash
# Auto-detect IP location and update android/gradle/wrapper/gradle-wrapper.properties

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GRADLE_PROP="$PROJECT_DIR/android/gradle/wrapper/gradle-wrapper.properties"

if [ ! -f "$GRADLE_PROP" ]; then
  echo "Warning: $GRADLE_PROP not found."
  exit 0
fi

echo "Auto-detecting IP location for Gradle distribution..."

COUNTRY_CODE=""

# Try primary API
RES=$(curl -s --max-time 3 http://ip-api.com/json 2>/dev/null)
if [ -n "$RES" ]; then
  COUNTRY_CODE=$(echo "$RES" | grep -o '"countryCode":"[^"]*' | cut -d'"' -f4)
fi

# Try fallback API if primary failed
if [ -z "$COUNTRY_CODE" ]; then
  RES=$(curl -s --max-time 3 https://ipinfo.io/json 2>/dev/null)
  if [ -n "$RES" ]; then
    COUNTRY_CODE=$(echo "$RES" | grep -o '"country":"[^"]*' | cut -d'"' -f4)
  fi
fi

OFFICIAL_URL="https\\://services.gradle.org/distributions/gradle-8.11.1-all.zip"
DOMESTIC_URL="https\\://mirrors.cloud.tencent.com/gradle/gradle-8.11.1-all.zip"

if [ "$COUNTRY_CODE" = "CN" ]; then
  echo "Detected domestic IP (CN). Using Tencent Cloud Gradle mirror."
  TARGET_URL="$DOMESTIC_URL"
elif [ -n "$COUNTRY_CODE" ]; then
  echo "Detected overseas IP ($COUNTRY_CODE). Using official Gradle distribution."
  TARGET_URL="$OFFICIAL_URL"
else
  echo "Could not determine IP location. Defaulting to official Gradle distribution."
  TARGET_URL="$OFFICIAL_URL"
fi

sed -i "s|distributionUrl=.*|distributionUrl=$TARGET_URL|" "$GRADLE_PROP"
echo "Updated distributionUrl in $GRADLE_PROP:"
grep "^distributionUrl=" "$GRADLE_PROP"

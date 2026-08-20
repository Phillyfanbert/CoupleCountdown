// generate-altsource.js — builds the AltStore/SideStore "source" manifest
// for the CI-produced .ipa (see .github/workflows/build.yml,
// build-device-ipa job). Both apps understand this JSON format as an
// addable source, so the app can show up with install/update buttons
// inside SideStore itself rather than needing a fresh manual download
// every time this repo changes.

const fs = require("fs");

const sha = (process.env.GITHUB_SHA || "unknown").slice(0, 7);
const size = parseInt(process.env.IPA_SIZE, 10);

const manifest = {
  name: "CoupleCountdown",
  identifier: "com.couplecountdown.altsource",
  apps: [
    {
      name: "CoupleCountdown",
      bundleIdentifier: "com.couplecountdown.app",
      developerName: "Philbert Fan",
      version: `main-${sha}`,
      versionDate: new Date().toISOString(),
      versionDescription: "Latest build from main.",
      downloadURL:
        "https://github.com/Phillyfanbert/CoupleCountdown/releases/download/latest/CoupleCountdown.ipa",
      localizedDescription: "A shared countdown for long-distance couples.",
      size,
    },
  ],
  news: [],
};

fs.writeFileSync("source.json", JSON.stringify(manifest, null, 2));

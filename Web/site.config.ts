export const site = {
  name: "DuoFX",
  tagline: "A softer close.",
  description:
    "A native macOS menu-bar app that animates your desktop as the MacBook lid closes — blur sweep, soft fold, or perspective tilt. Free, open source, 100% local.",
  url: "https://duofx.amjadjibon.com",
  version: "0.2.0",
  requirements: "macOS 14 Sonoma or later · Apple silicon",
  license: "Apache-2.0",
  author: { name: "Amjad Hossain", url: "https://amjadjibon.com" },

  repoUrl: "https://github.com/amjadjibon/DuoFX",
  releasesUrl: "https://github.com/amjadjibon/DuoFX/releases/latest",
  sponsorUrl: "https://github.com/sponsors/amjadjibon",
  brewCommand: "brew install --cask amjadjibon/tap/duofx",
} as const;

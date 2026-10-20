export const REPO = 'https://github.com/ppazosp/gitisle';
// The site serves scripts/install.sh (copied at build time), so the command stays short.
export const INSTALL_SCRIPT = 'curl -fsSL https://gitisle.ppazosp.dev/install.sh | bash';
// Homebrew finds the ppazosp/homebrew-gitisle tap by itself.
export const BREW = 'brew install --cask ppazosp/gitisle/gitisle';
export const RELEASES = `${REPO}/releases/latest`;
export const DMG = `${RELEASES}/download/GitIsle.dmg`;

export const CHANNELS = [
  { name: 'LinkedIn', handle: 'pablo-pazos-parada', href: 'https://www.linkedin.com/in/pablo-pazos-parada/' },
  { name: 'X', handle: '@ppazosp', href: 'https://x.com/ppazosp' },
  { name: 'GitHub', handle: 'ppazosp', href: 'https://github.com/ppazosp' },
] as const;

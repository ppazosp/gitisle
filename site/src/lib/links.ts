export const REPO = 'https://github.com/ppazosp/gitisle';
export const INSTALL_SCRIPT =
  'curl -fsSL https://raw.githubusercontent.com/ppazosp/gitisle/main/scripts/install.sh | bash';
export const BREW = [
  'brew tap ppazosp/gitisle https://github.com/ppazosp/gitisle',
  'brew install --cask gitisle',
];
export const RELEASES = `${REPO}/releases/latest`;

export const CHANNELS = [
  { name: 'LinkedIn', handle: 'pablo-pazos-parada', href: 'https://www.linkedin.com/in/pablo-pazos-parada/' },
  { name: 'X', handle: '@ppazosp', href: 'https://x.com/ppazosp' },
  { name: 'GitHub', handle: 'ppazosp', href: 'https://github.com/ppazosp' },
] as const;

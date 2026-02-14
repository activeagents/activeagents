import React from 'react';

/**
 * Modular Agent Avatar Component
 *
 * A composable SVG component for rendering ActiveAgents mascot with
 * customizable hats, accessories, and held items.
 *
 * @example
 * <AgentAvatar
 *   hat="fedora"
 *   hatAccessory="feather"
 *   heldItem="terminal"
 *   primaryColor="#E86B6B"
 *   size={200}
 * />
 */

// Color palette presets for different agent types
export const AGENT_THEMES = {
  default: { primary: '#E86B6B', secondary: '#D45A5A', highlight: '#F28B8B' },
  terminal: { primary: '#E86B6B', secondary: '#D45A5A', highlight: '#F28B8B' },
  research: { primary: '#E86B6B', secondary: '#D45A5A', highlight: '#F28B8B' },
  translation: { primary: '#E86B6B', secondary: '#D45A5A', highlight: '#F28B8B' },
  writing: { primary: '#E86B6B', secondary: '#D45A5A', highlight: '#F28B8B' },
  // Future: could add color variants
  // blue: { primary: '#6B8BE8', secondary: '#5A6BD4', highlight: '#8BA0F2' },
};

// Hat configurations
const HATS = {
  fedora: ({ colors }) => (
    <g id="hat-fedora">
      <defs>
        <linearGradient id="hatGradient" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#5A5A5A"/>
          <stop offset="100%" stopColor="#3A3A3A"/>
        </linearGradient>
      </defs>
      <ellipse cx="100" cy="65" rx="70" ry="12" fill="#3A3A3A"/>
      <path d="M 40 65 Q 40 25 70 20 L 130 20 Q 160 25 160 65 Z" fill="url(#hatGradient)"/>
      <rect x="45" y="50" width="110" height="8" fill="#2D2D2D" rx="2"/>
      <path d="M 70 20 Q 100 35 130 20" fill="none" stroke="#4A4A4A" strokeWidth="3"/>
    </g>
  ),

  safari: ({ colors }) => (
    <g id="hat-safari">
      <defs>
        <linearGradient id="safariGradient" x1="0%" y1="0%" x2="0%" y2="100%">
          <stop offset="0%" stopColor="#D4C4A8"/>
          <stop offset="100%" stopColor="#B8A88C"/>
        </linearGradient>
      </defs>
      <ellipse cx="100" cy="68" rx="80" ry="10" fill="#A89878"/>
      <ellipse cx="100" cy="40" rx="45" ry="30" fill="url(#safariGradient)"/>
      <path d="M 58 55 Q 100 65 142 55" fill="none" stroke="#6B5B45" strokeWidth="4"/>
      <circle cx="55" cy="68" r="3" fill="#5A4A3A"/>
      <circle cx="145" cy="68" r="3" fill="#5A4A3A"/>
    </g>
  ),
};

// Hat accessories
const HAT_ACCESSORIES = {
  feather: () => (
    <g id="accessory-feather" transform="translate(145, -15) rotate(15)">
      <path d="M 20 75 Q 18 40 25 5" fill="none" stroke="#8B8B8B" strokeWidth="2"/>
      <path d="M 20 70 Q 5 65 8 55 Q 15 58 18 50 Q 3 48 6 38 Q 14 42 17 35 Q 5 30 10 20 Q 16 28 20 25" fill="#C0C0C0" stroke="#A0A0A0" strokeWidth="0.5"/>
      <path d="M 22 65 Q 35 62 32 52 Q 26 55 24 48 Q 37 45 33 35 Q 27 40 25 32 Q 35 28 30 18 Q 26 25 25 20" fill="#D8D8D8" stroke="#B8B8B8" strokeWidth="0.5"/>
    </g>
  ),

  cherryBlossom: () => (
    <g id="accessory-cherry-blossom" transform="translate(140, 15) scale(0.8)">
      <defs>
        <radialGradient id="petalGradient" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#FFCCD5"/>
          <stop offset="100%" stopColor="#FFB3C1"/>
        </radialGradient>
      </defs>
      <ellipse cx="25" cy="12" rx="8" ry="12" fill="url(#petalGradient)" transform="rotate(0 25 25)"/>
      <ellipse cx="25" cy="12" rx="8" ry="12" fill="url(#petalGradient)" transform="rotate(72 25 25)"/>
      <ellipse cx="25" cy="12" rx="8" ry="12" fill="url(#petalGradient)" transform="rotate(144 25 25)"/>
      <ellipse cx="25" cy="12" rx="8" ry="12" fill="url(#petalGradient)" transform="rotate(216 25 25)"/>
      <ellipse cx="25" cy="12" rx="8" ry="12" fill="url(#petalGradient)" transform="rotate(288 25 25)"/>
      <circle cx="25" cy="25" r="6" fill="#FFE5E5"/>
      <circle cx="23" cy="23" r="1.5" fill="#FFD700"/>
      <circle cx="27" cy="23" r="1.5" fill="#FFD700"/>
      <circle cx="25" cy="27" r="1.5" fill="#FFD700"/>
    </g>
  ),

  theaterMasks: () => (
    <g id="accessory-theater-masks" transform="translate(80, 25) scale(0.8)">
      <circle cx="20" cy="20" r="18" fill="#1A6B8A" stroke="#D4A530" strokeWidth="3"/>
      <g transform="translate(-2, 2) scale(0.7)">
        <path d="M 18 12 Q 10 12 10 20 Q 10 28 18 28 Q 26 28 26 20 Q 26 12 18 12" fill="#FFFFFF" stroke="#1A6B8A" strokeWidth="1"/>
        <circle cx="14" cy="18" r="2" fill="#1A6B8A"/>
        <circle cx="22" cy="18" r="2" fill="#1A6B8A"/>
        <path d="M 14 23 Q 18 27 22 23" fill="none" stroke="#1A6B8A" strokeWidth="1.5"/>
      </g>
      <g transform="translate(8, 6) scale(0.7)">
        <path d="M 25 15 Q 17 15 17 23 Q 17 31 25 31 Q 33 31 33 23 Q 33 15 25 15" fill="#FFFFFF" stroke="#1A6B8A" strokeWidth="1"/>
        <circle cx="21" cy="21" r="2" fill="#1A6B8A"/>
        <circle cx="29" cy="21" r="2" fill="#1A6B8A"/>
        <path d="M 21 27 Q 25 24 29 27" fill="none" stroke="#1A6B8A" strokeWidth="1.5"/>
      </g>
    </g>
  ),
};

// Held items
const HELD_ITEMS = {
  terminal: () => (
    <g id="item-terminal" transform="translate(40, 115)">
      <rect x="0" y="0" width="120" height="80" rx="6" fill="#1E1E1E" stroke="#333" strokeWidth="2"/>
      <rect x="0" y="0" width="120" height="18" rx="6" fill="#333333"/>
      <rect x="0" y="12" width="120" height="6" fill="#333333"/>
      <circle cx="12" cy="9" r="4" fill="#FF5F56"/>
      <circle cx="26" cy="9" r="4" fill="#FFBD2E"/>
      <circle cx="40" cy="9" r="4" fill="#27CA3F"/>
      <text x="8" y="35" fontFamily="monospace" fontSize="9" fill="#00FF00">$ ls -la</text>
      <text x="8" y="47" fontFamily="monospace" fontSize="8" fill="#CCCCCC">drwxr-xr-x  agents/</text>
      <text x="8" y="57" fontFamily="monospace" fontSize="8" fill="#CCCCCC">-rw-r--r--  config.rb</text>
      <text x="8" y="67" fontFamily="monospace" fontSize="9" fill="#00FF00">$ _</text>
      <rect x="18" y="60" width="6" height="10" fill="#00FF00" opacity="0.8"/>
    </g>
  ),

  browser: () => (
    <g id="item-browser" transform="translate(40, 115)">
      <rect x="0" y="0" width="120" height="90" rx="6" fill="#FFFFFF" stroke="#E0E0E0" strokeWidth="2"/>
      <rect x="0" y="0" width="120" height="20" rx="6" fill="#F5F5F5"/>
      <rect x="0" y="14" width="120" height="6" fill="#F5F5F5"/>
      <circle cx="12" cy="10" r="4" fill="#FF5F56"/>
      <circle cx="26" cy="10" r="4" fill="#FFBD2E"/>
      <circle cx="40" cy="10" r="4" fill="#27CA3F"/>
      <rect x="50" y="5" width="60" height="10" rx="3" fill="#FFFFFF" stroke="#DDD" strokeWidth="1"/>
      <rect x="8" y="28" width="30" height="50" rx="2" fill="#4A90D9"/>
      <rect x="44" y="28" width="68" height="8" rx="2" fill="#E8E8E8"/>
      <rect x="44" y="40" width="60" height="6" rx="1" fill="#F0F0F0"/>
      <rect x="44" y="50" width="55" height="6" rx="1" fill="#F0F0F0"/>
      <rect x="44" y="60" width="50" height="6" rx="1" fill="#F0F0F0"/>
      <rect x="44" y="72" width="25" height="8" rx="2" fill="#E86B6B"/>
    </g>
  ),

  document: () => (
    <g id="item-document" transform="translate(60, 115)">
      <path d="M 5 0 L 55 0 L 75 20 L 75 100 L 5 100 Z" fill="#FFFFFF" stroke="#CCCCCC" strokeWidth="2"/>
      <path d="M 55 0 L 55 20 L 75 20 Z" fill="#E8E8E8" stroke="#CCCCCC" strokeWidth="1"/>
      <rect x="12" y="30" width="50" height="4" rx="1" fill="#E0E0E0"/>
      <rect x="12" y="40" width="45" height="4" rx="1" fill="#E0E0E0"/>
      <rect x="12" y="50" width="48" height="4" rx="1" fill="#E0E0E0"/>
      <rect x="12" y="60" width="35" height="4" rx="1" fill="#E0E0E0"/>
      <rect x="12" y="75" width="50" height="4" rx="1" fill="#E0E0E0"/>
      <rect x="12" y="85" width="40" height="4" rx="1" fill="#E0E0E0"/>
      <rect x="10" y="8" width="28" height="14" rx="2" fill="#E86B6B"/>
      <text x="14" y="18" fontFamily="sans-serif" fontSize="8" fontWeight="bold" fill="#FFFFFF">PDF</text>
    </g>
  ),

  scroll: () => (
    <g id="item-scroll" transform="translate(65, 110)">
      <defs>
        <linearGradient id="parchmentGradient" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="#F5E6C8"/>
          <stop offset="50%" stopColor="#FDF8EE"/>
          <stop offset="100%" stopColor="#F5E6C8"/>
        </linearGradient>
      </defs>
      <ellipse cx="35" cy="8" rx="30" ry="8" fill="#D4C4A0"/>
      <rect x="5" y="8" width="60" height="6" fill="url(#parchmentGradient)"/>
      <rect x="8" y="14" width="54" height="65" fill="url(#parchmentGradient)"/>
      <ellipse cx="35" cy="79" rx="30" ry="8" fill="#D4C4A0"/>
      <path d="M 15 25 Q 25 23 35 25 Q 45 27 50 25" fill="none" stroke="#8B7355" strokeWidth="1.5"/>
      <path d="M 15 35 Q 30 33 45 35" fill="none" stroke="#8B7355" strokeWidth="1.5"/>
      <path d="M 15 45 Q 28 43 42 45 Q 48 46 52 45" fill="none" stroke="#8B7355" strokeWidth="1.5"/>
      <path d="M 15 55 Q 22 53 35 55" fill="none" stroke="#8B7355" strokeWidth="1.5"/>
      <path d="M 15 65 Q 32 63 48 65" fill="none" stroke="#8B7355" strokeWidth="1.5"/>
    </g>
  ),

  magnifyingGlass: () => (
    <g id="item-magnifying-glass" transform="translate(130, 100) scale(1.2)">
      <defs>
        <linearGradient id="glassGradient" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.9"/>
          <stop offset="50%" stopColor="#E8F4FC" stopOpacity="0.6"/>
          <stop offset="100%" stopColor="#B8D4E8" stopOpacity="0.4"/>
        </linearGradient>
      </defs>
      <rect x="42" y="42" width="8" height="20" rx="3" fill="#4A4A4A" transform="rotate(45 46 52)"/>
      <circle cx="25" cy="25" r="22" fill="none" stroke="#5A5A5A" strokeWidth="5"/>
      <circle cx="25" cy="25" r="18" fill="url(#glassGradient)"/>
      <path d="M 15 15 Q 12 20 15 25" fill="none" stroke="#FFFFFF" strokeWidth="3" strokeLinecap="round" opacity="0.8"/>
    </g>
  ),
};

// Base body component
const AgentBody = ({ colors }) => (
  <g id="body">
    <defs>
      <linearGradient id="gemGradient" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor={colors.highlight}/>
        <stop offset="50%" stopColor={colors.primary}/>
        <stop offset="100%" stopColor={colors.secondary}/>
      </linearGradient>
      <radialGradient id="blush" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#FFB5B5" stopOpacity="0.8"/>
        <stop offset="100%" stopColor="#FFB5B5" stopOpacity="0"/>
      </radialGradient>
      <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="2" dy="4" stdDeviation="3" floodOpacity="0.15"/>
      </filter>
      <linearGradient id="handGradient" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stopColor={colors.highlight}/>
        <stop offset="100%" stopColor={colors.secondary}/>
      </linearGradient>
    </defs>

    {/* Gem body */}
    <g filter="url(#shadow)">
      <polygon
        points="100,25 155,50 175,100 155,150 100,175 45,150 25,100 45,50"
        fill="url(#gemGradient)"
        stroke={colors.secondary}
        strokeWidth="2"
      />
      {/* Highlight facet */}
      <polygon
        points="100,25 155,50 140,75 100,45 60,75 45,50"
        fill={colors.highlight}
        opacity="0.5"
      />
    </g>

    {/* Face */}
    <g id="face">
      {/* Left Eye */}
      <ellipse cx="75" cy="95" rx="12" ry="14" fill="#2D2D2D"/>
      <ellipse cx="78" cy="91" rx="4" ry="5" fill="#FFFFFF"/>

      {/* Right Eye */}
      <ellipse cx="125" cy="95" rx="12" ry="14" fill="#2D2D2D"/>
      <ellipse cx="128" cy="91" rx="4" ry="5" fill="#FFFFFF"/>

      {/* Smile */}
      <path
        d="M 85 115 Q 100 130 115 115"
        fill="none"
        stroke="#2D2D2D"
        strokeWidth="3"
        strokeLinecap="round"
      />

      {/* Cheeks */}
      <ellipse cx="55" cy="110" rx="12" ry="8" fill="url(#blush)"/>
      <ellipse cx="145" cy="110" rx="12" ry="8" fill="url(#blush)"/>
    </g>

    {/* Hands */}
    <g id="hands">
      <ellipse cx="25" cy="140" rx="18" ry="16" fill="url(#handGradient)" stroke={colors.secondary} strokeWidth="1.5"/>
      <ellipse cx="175" cy="140" rx="18" ry="16" fill="url(#handGradient)" stroke={colors.secondary} strokeWidth="1.5"/>
    </g>
  </g>
);

/**
 * AgentAvatar - Composable agent avatar component
 *
 * @param {string} hat - Hat type: 'fedora' | 'safari'
 * @param {string} hatAccessory - Hat accessory: 'feather' | 'cherryBlossom' | 'theaterMasks'
 * @param {string} heldItem - Held item: 'terminal' | 'browser' | 'document' | 'scroll' | 'magnifyingGlass'
 * @param {string} theme - Color theme from AGENT_THEMES
 * @param {object} customColors - Custom colors { primary, secondary, highlight }
 * @param {number} size - Size in pixels (default: 200)
 * @param {string} className - Additional CSS classes
 */
export default function AgentAvatar({
  hat = 'fedora',
  hatAccessory = null,
  heldItem = null,
  theme = 'default',
  customColors = null,
  size = 200,
  className = '',
}) {
  const colors = customColors || AGENT_THEMES[theme] || AGENT_THEMES.default;
  const HatComponent = HATS[hat];
  const HatAccessoryComponent = hatAccessory ? HAT_ACCESSORIES[hatAccessory] : null;
  const HeldItemComponent = heldItem ? HELD_ITEMS[heldItem] : null;

  // Calculate viewBox based on whether we have held items (they extend below)
  const viewBoxHeight = heldItem ? 220 : 180;

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox={`0 0 200 ${viewBoxHeight}`}
      width={size}
      height={size * (viewBoxHeight / 200)}
      className={className}
    >
      {/* Layer 1: Body & Face & Hands */}
      <AgentBody colors={colors} />

      {/* Layer 2: Hat */}
      {HatComponent && (
        <g transform="translate(0, -40)">
          <HatComponent colors={colors} />
        </g>
      )}

      {/* Layer 3: Hat Accessory */}
      {HatAccessoryComponent && (
        <g transform="translate(0, -40)">
          <HatAccessoryComponent />
        </g>
      )}

      {/* Layer 4: Held Item */}
      {HeldItemComponent && <HeldItemComponent />}
    </svg>
  );
}

// Preset configurations for built-in agent types
export const AGENT_PRESETS = {
  terminal: { hat: 'fedora', heldItem: 'terminal' },
  webDeveloper: { hat: 'fedora', heldItem: 'browser' },
  documentAnalysis: { hat: 'fedora', heldItem: 'document', hatAccessory: 'magnifyingGlass' },
  writing: { hat: 'fedora', hatAccessory: 'feather', heldItem: 'scroll' },
  translation: { hat: 'fedora', hatAccessory: 'cherryBlossom' },
  playwright: { hat: 'fedora', hatAccessory: 'theaterMasks' },
  research: { hat: 'safari', heldItem: 'magnifyingGlass' },
  imageAnalysis: { hat: 'fedora', heldItem: 'document' },
  computerUse: { hat: 'fedora', heldItem: 'browser' },
  productDesign: { hat: 'fedora', heldItem: 'browser' },
};

// Helper component for using presets
export function PresetAgentAvatar({ preset, size = 200, className = '' }) {
  const config = AGENT_PRESETS[preset] || AGENT_PRESETS.terminal;
  return <AgentAvatar {...config} size={size} className={className} />;
}

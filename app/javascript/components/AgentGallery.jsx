import React from 'react';
import AgentAvatar, { AGENT_PRESETS, PresetAgentAvatar } from './AgentAvatar';

/**
 * AgentGallery - Showcase all agent avatar variations
 *
 * Inspired by GitHub's Octodex, this component displays all the
 * built-in agent personas with their unique accessories and items.
 */

const AGENT_INFO = {
  terminal: {
    name: 'Terminal Agent',
    description: 'Command-line operations and shell scripting',
    icon: '💻',
  },
  webDeveloper: {
    name: 'Web Developer Agent',
    description: 'Building and debugging web applications',
    icon: '🌐',
  },
  documentAnalysis: {
    name: 'Document Analysis Agent',
    description: 'Parsing and extracting insights from documents',
    icon: '📄',
  },
  writing: {
    name: 'Writing Agent',
    description: 'Creative and technical content creation',
    icon: '✍️',
  },
  translation: {
    name: 'Translation Agent',
    description: 'Multi-language translation and localization',
    icon: '🌸',
  },
  playwright: {
    name: 'Playwright Agent',
    description: 'Browser automation and testing',
    icon: '🎭',
  },
  research: {
    name: 'Research Agent',
    description: 'Web search and information gathering',
    icon: '🔍',
  },
  imageAnalysis: {
    name: 'Image Analysis Agent',
    description: 'Visual content understanding and processing',
    icon: '🖼️',
  },
  computerUse: {
    name: 'Computer Use Agent',
    description: 'Desktop automation and GUI interaction',
    icon: '🖥️',
  },
  productDesign: {
    name: 'Product Design Agent',
    description: 'UI/UX design and prototyping',
    icon: '🎨',
  },
};

function AgentCard({ preset, size = 180 }) {
  const info = AGENT_INFO[preset] || { name: preset, description: '', icon: '🤖' };

  return (
    <div className="agent-card">
      <div className="agent-avatar-wrapper">
        <PresetAgentAvatar preset={preset} size={size} />
      </div>
      <div className="agent-info">
        <h3 className="agent-name">
          <span className="agent-icon">{info.icon}</span>
          {info.name}
        </h3>
        <p className="agent-description">{info.description}</p>
      </div>
    </div>
  );
}

export default function AgentGallery({ columns = 3 }) {
  const presets = Object.keys(AGENT_PRESETS);

  return (
    <div className="agent-gallery">
      <header className="gallery-header">
        <h1>Agent Gallery</h1>
        <p>Meet the ActiveAgents family - modular AI assistants ready to help with any task.</p>
      </header>

      <div
        className="gallery-grid"
        style={{
          display: 'grid',
          gridTemplateColumns: `repeat(${columns}, 1fr)`,
          gap: '2rem',
          padding: '2rem',
        }}
      >
        {presets.map((preset) => (
          <AgentCard key={preset} preset={preset} />
        ))}
      </div>

      <style>{`
        .agent-gallery {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
          max-width: 1200px;
          margin: 0 auto;
        }

        .gallery-header {
          text-align: center;
          padding: 3rem 2rem;
        }

        .gallery-header h1 {
          font-size: 2.5rem;
          margin-bottom: 0.5rem;
          background: linear-gradient(135deg, #E86B6B, #D45A5A);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
        }

        .gallery-header p {
          color: #666;
          font-size: 1.1rem;
        }

        .agent-card {
          background: #fff;
          border-radius: 16px;
          padding: 1.5rem;
          box-shadow: 0 4px 20px rgba(0, 0, 0, 0.08);
          transition: transform 0.2s ease, box-shadow 0.2s ease;
          text-align: center;
        }

        .agent-card:hover {
          transform: translateY(-4px);
          box-shadow: 0 8px 30px rgba(0, 0, 0, 0.12);
        }

        .agent-avatar-wrapper {
          display: flex;
          justify-content: center;
          margin-bottom: 1rem;
        }

        .agent-info {
          padding-top: 0.5rem;
          border-top: 1px solid #f0f0f0;
        }

        .agent-name {
          font-size: 1.1rem;
          font-weight: 600;
          margin: 0.5rem 0;
          color: #333;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
        }

        .agent-icon {
          font-size: 1.2rem;
        }

        .agent-description {
          font-size: 0.9rem;
          color: #666;
          margin: 0;
          line-height: 1.4;
        }

        @media (max-width: 900px) {
          .gallery-grid {
            grid-template-columns: repeat(2, 1fr) !important;
          }
        }

        @media (max-width: 600px) {
          .gallery-grid {
            grid-template-columns: 1fr !important;
          }
        }
      `}</style>
    </div>
  );
}

/**
 * AgentBuilder - Interactive agent customization component
 *
 * Allows users to mix and match different hats, accessories, and items
 * to create custom agent avatars.
 */
export function AgentBuilder() {
  const [config, setConfig] = React.useState({
    hat: 'fedora',
    hatAccessory: null,
    heldItem: 'terminal',
  });

  const hats = ['fedora', 'safari'];
  const accessories = [null, 'feather', 'cherryBlossom', 'theaterMasks'];
  const items = [null, 'terminal', 'browser', 'document', 'scroll', 'magnifyingGlass'];

  return (
    <div className="agent-builder">
      <div className="builder-preview">
        <AgentAvatar {...config} size={280} />
      </div>

      <div className="builder-controls">
        <div className="control-group">
          <label>Hat Style</label>
          <div className="button-group">
            {hats.map((hat) => (
              <button
                key={hat}
                className={config.hat === hat ? 'active' : ''}
                onClick={() => setConfig({ ...config, hat })}
              >
                {hat}
              </button>
            ))}
          </div>
        </div>

        <div className="control-group">
          <label>Hat Accessory</label>
          <div className="button-group">
            {accessories.map((acc) => (
              <button
                key={acc || 'none'}
                className={config.hatAccessory === acc ? 'active' : ''}
                onClick={() => setConfig({ ...config, hatAccessory: acc })}
              >
                {acc || 'None'}
              </button>
            ))}
          </div>
        </div>

        <div className="control-group">
          <label>Held Item</label>
          <div className="button-group">
            {items.map((item) => (
              <button
                key={item || 'none'}
                className={config.heldItem === item ? 'active' : ''}
                onClick={() => setConfig({ ...config, heldItem: item })}
              >
                {item || 'None'}
              </button>
            ))}
          </div>
        </div>
      </div>

      <style>{`
        .agent-builder {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 2rem;
          padding: 2rem;
          max-width: 600px;
          margin: 0 auto;
        }

        .builder-preview {
          background: linear-gradient(135deg, #f8f9fa, #e9ecef);
          border-radius: 20px;
          padding: 2rem;
        }

        .builder-controls {
          width: 100%;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }

        .control-group {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }

        .control-group label {
          font-weight: 600;
          color: #333;
          font-size: 0.9rem;
        }

        .button-group {
          display: flex;
          flex-wrap: wrap;
          gap: 0.5rem;
        }

        .button-group button {
          padding: 0.5rem 1rem;
          border: 2px solid #e0e0e0;
          border-radius: 8px;
          background: white;
          cursor: pointer;
          font-size: 0.85rem;
          text-transform: capitalize;
          transition: all 0.2s ease;
        }

        .button-group button:hover {
          border-color: #E86B6B;
        }

        .button-group button.active {
          background: #E86B6B;
          border-color: #E86B6B;
          color: white;
        }
      `}</style>
    </div>
  );
}

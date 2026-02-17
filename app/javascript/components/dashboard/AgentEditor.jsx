import React, { useState, useEffect } from 'react';
import AgentAvatar, { AGENT_PRESETS } from '../AgentAvatar';

const TABS = [
  { id: 'config', label: 'Configuration', icon: '⚙️' },
  { id: 'instructions', label: 'Instructions', icon: '📝' },
  { id: 'tools', label: 'Tools', icon: '🛠️' },
  { id: 'versions', label: 'Versions', icon: '📚' },
  { id: 'code', label: 'Code', icon: '💻' }
];

const PROVIDER_MODELS = {
  openai: ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'gpt-3.5-turbo'],
  anthropic: ['claude-sonnet-4-20250514', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229'],
  ollama: ['llama3', 'mistral', 'codellama', 'mixtral'],
  openrouter: ['openai/gpt-4o', 'anthropic/claude-sonnet-4-20250514', 'meta-llama/llama-3-70b-instruct']
};

export default function AgentEditor({ agent, meta, onSave, onDelete, onRun, onBack, isLoading }) {
  const [activeTab, setActiveTab] = useState('config');
  const [formData, setFormData] = useState({
    name: agent.name || '',
    description: agent.description || '',
    provider: agent.provider || 'openai',
    model: agent.model || 'gpt-4o-mini',
    instructions: agent.instructions || '',
    preset_type: agent.presetType || agent.preset_type || 'terminal',
    appearance: agent.appearance || {},
    instruction_sets: agent.instructionSets || agent.instruction_sets || [],
    tools: agent.tools || [],
    mcp_servers: agent.mcpServers || agent.mcp_servers || [],
    model_config: agent.modelConfig || agent.model_config || { temperature: 0.7 },
    status: agent.status || 'draft'
  });
  const [versions, setVersions] = useState([]);
  const [hasChanges, setHasChanges] = useState(false);
  const [codePreview, setCodePreview] = useState('');

  useEffect(() => {
    // Check for unsaved changes
    const changed = JSON.stringify(formData) !== JSON.stringify({
      name: agent.name || '',
      description: agent.description || '',
      provider: agent.provider || 'openai',
      model: agent.model || 'gpt-4o-mini',
      instructions: agent.instructions || '',
      preset_type: agent.presetType || agent.preset_type || 'terminal',
      appearance: agent.appearance || {},
      instruction_sets: agent.instructionSets || agent.instruction_sets || [],
      tools: agent.tools || [],
      mcp_servers: agent.mcpServers || agent.mcp_servers || [],
      model_config: agent.modelConfig || agent.model_config || { temperature: 0.7 },
      status: agent.status || 'draft'
    });
    setHasChanges(changed);
  }, [formData, agent]);

  useEffect(() => {
    if (activeTab === 'versions') {
      loadVersions();
    } else if (activeTab === 'code') {
      loadCodePreview();
    }
  }, [activeTab]);

  const loadVersions = async () => {
    try {
      const response = await fetch(`/api/agents/${agent.id}/versions`);
      const data = await response.json();
      setVersions(data.versions);
    } catch (error) {
      console.error('Failed to load versions:', error);
    }
  };

  const loadCodePreview = async () => {
    try {
      const response = await fetch(`/api/agents/${agent.id}/export`);
      const data = await response.json();
      setCodePreview(data.code);
    } catch (error) {
      console.error('Failed to load code preview:', error);
    }
  };

  const updateField = (field, value) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const toggleArrayItem = (field, item) => {
    setFormData(prev => {
      const current = prev[field] || [];
      const updated = current.includes(item)
        ? current.filter(i => i !== item)
        : [...current, item];
      return { ...prev, [field]: updated };
    });
  };

  const handleSave = () => {
    onSave(formData);
  };

  const getAppearanceConfig = () => {
    const presetConfig = AGENT_PRESETS[formData.preset_type] || {};
    return { ...presetConfig, ...formData.appearance };
  };

  const appearance = getAppearanceConfig();

  return (
    <div className="grid grid-cols-3 gap-6 h-full">
      {/* Main Editor */}
      <div className="col-span-2 space-y-4">
        {/* Tabs */}
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <div className="flex border-b border-gray-200">
            {TABS.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center space-x-2 px-6 py-3 text-sm font-medium transition-colors ${
                  activeTab === tab.id
                    ? 'text-rose-600 border-b-2 border-rose-500 bg-rose-50'
                    : 'text-gray-500 hover:text-gray-700 hover:bg-gray-50'
                }`}
              >
                <span>{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>

          <div className="p-6">
            {activeTab === 'config' && (
              <ConfigTab formData={formData} updateField={updateField} providerModels={PROVIDER_MODELS} />
            )}
            {activeTab === 'instructions' && (
              <InstructionsTab formData={formData} updateField={updateField} meta={meta} toggleArrayItem={toggleArrayItem} />
            )}
            {activeTab === 'tools' && (
              <ToolsTab formData={formData} meta={meta} toggleArrayItem={toggleArrayItem} />
            )}
            {activeTab === 'versions' && (
              <VersionsTab versions={versions} agentId={agent.id} onRestore={loadVersions} />
            )}
            {activeTab === 'code' && (
              <CodeTab code={codePreview} />
            )}
          </div>
        </div>
      </div>

      {/* Sidebar Preview */}
      <div className="space-y-4">
        {/* Preview Card */}
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <div className="h-48 bg-gradient-to-br from-gray-50 to-gray-100 flex items-center justify-center">
            <AgentAvatar
              hat={appearance.hat}
              hatAccessory={appearance.hatAccessory}
              heldItem={appearance.heldItem}
              size={140}
            />
          </div>
          <div className="p-4 border-t border-gray-100">
            <h3 className="font-semibold text-gray-900">{formData.name}</h3>
            <p className="text-sm text-gray-500 mt-1">{formData.description || 'No description'}</p>
            <div className="mt-3 flex items-center space-x-2 text-xs text-gray-400">
              <span className="px-2 py-1 bg-gray-100 rounded">{formData.provider}</span>
              <span>{formData.model}</span>
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
          <button
            onClick={onRun}
            className="w-full flex items-center justify-center space-x-2 px-4 py-2 bg-emerald-500 text-white rounded-lg hover:bg-emerald-600 transition-colors"
          >
            <span>▶️</span>
            <span>Run Agent</span>
          </button>

          <button
            onClick={handleSave}
            disabled={!hasChanges || isLoading}
            className={`w-full flex items-center justify-center space-x-2 px-4 py-2 rounded-lg transition-colors ${
              hasChanges && !isLoading
                ? 'bg-rose-500 text-white hover:bg-rose-600'
                : 'bg-gray-100 text-gray-400 cursor-not-allowed'
            }`}
          >
            <span>💾</span>
            <span>{hasChanges ? 'Save Changes' : 'No Changes'}</span>
          </button>

          <div className="flex space-x-2">
            <button
              onClick={onBack}
              className="flex-1 px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition-colors"
            >
              Back
            </button>
            <button
              onClick={onDelete}
              className="px-4 py-2 border border-red-300 text-red-500 rounded-lg hover:bg-red-50 transition-colors"
            >
              Delete
            </button>
          </div>
        </div>

        {/* Status */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <label className="block text-sm font-medium text-gray-700 mb-2">Status</label>
          <select
            value={formData.status}
            onChange={(e) => updateField('status', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
          >
            <option value="draft">Draft</option>
            <option value="active">Active</option>
            <option value="archived">Archived</option>
          </select>
        </div>

        {/* Quick Stats */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <h4 className="text-sm font-medium text-gray-700 mb-3">Quick Stats</h4>
          <div className="grid grid-cols-2 gap-3 text-center">
            <div className="p-3 bg-gray-50 rounded-lg">
              <div className="text-lg font-semibold text-gray-900">{formData.tools.length}</div>
              <div className="text-xs text-gray-500">Tools</div>
            </div>
            <div className="p-3 bg-gray-50 rounded-lg">
              <div className="text-lg font-semibold text-gray-900">{agent.versionCount || agent.version_count || 1}</div>
              <div className="text-xs text-gray-500">Versions</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function ConfigTab({ formData, updateField, providerModels }) {
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Agent Name</label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => updateField('name', e.target.value)}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Preset Type</label>
          <select
            value={formData.preset_type}
            onChange={(e) => updateField('preset_type', e.target.value)}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
          >
            {Object.keys(AGENT_PRESETS).map(preset => (
              <option key={preset} value={preset}>{preset}</option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
        <textarea
          value={formData.description}
          onChange={(e) => updateField('description', e.target.value)}
          rows={3}
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Provider</label>
          <select
            value={formData.provider}
            onChange={(e) => {
              updateField('provider', e.target.value);
              updateField('model', providerModels[e.target.value][0]);
            }}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
          >
            {Object.keys(providerModels).map(p => (
              <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Model</label>
          <select
            value={formData.model}
            onChange={(e) => updateField('model', e.target.value)}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
          >
            {providerModels[formData.provider]?.map(m => (
              <option key={m} value={m}>{m}</option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Temperature: {formData.model_config.temperature}
        </label>
        <input
          type="range"
          min="0"
          max="1"
          step="0.1"
          value={formData.model_config.temperature}
          onChange={(e) => updateField('model_config', { ...formData.model_config, temperature: parseFloat(e.target.value) })}
          className="w-full"
        />
      </div>
    </div>
  );
}

function InstructionsTab({ formData, updateField, meta, toggleArrayItem }) {
  return (
    <div className="space-y-6">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">System Instructions</label>
        <textarea
          value={formData.instructions}
          onChange={(e) => updateField('instructions', e.target.value)}
          placeholder="You are a helpful AI assistant..."
          rows={12}
          className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500 font-mono text-sm"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-3">Instruction Sets</label>
        <div className="flex flex-wrap gap-2">
          {meta.instructionSets?.map(instruction => (
            <button
              key={instruction}
              onClick={() => toggleArrayItem('instruction_sets', instruction)}
              className={`px-3 py-1.5 rounded-full text-sm transition-colors ${
                formData.instruction_sets.includes(instruction)
                  ? 'bg-rose-500 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {instruction}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function ToolsTab({ formData, meta, toggleArrayItem }) {
  const getToolIcon = (tool) => {
    const icons = {
      terminal: '💻', playwright: '🎭', filesystem: '📁', code: '📝',
      database: '🗄️', slack: '💬', fetch: '🌐', search: '🔍',
      edit: '✏️', translate: '🌍', memory: '🧠'
    };
    return icons[tool] || '🔧';
  };

  return (
    <div className="space-y-6">
      <p className="text-gray-500">Select the tools your agent can use.</p>

      <div className="grid grid-cols-4 gap-4">
        {meta.availableTools?.map(tool => (
          <button
            key={tool}
            onClick={() => toggleArrayItem('tools', tool)}
            className={`p-4 rounded-xl border-2 text-center transition-all ${
              formData.tools.includes(tool)
                ? 'border-rose-500 bg-rose-50 text-rose-700'
                : 'border-gray-200 hover:border-gray-300 text-gray-700'
            }`}
          >
            <span className="text-2xl block mb-2">{getToolIcon(tool)}</span>
            <span className="text-sm capitalize font-medium">{tool}</span>
          </button>
        ))}
      </div>

      {formData.tools.length > 0 && (
        <div className="p-4 bg-gray-50 rounded-lg">
          <h4 className="text-sm font-medium text-gray-700 mb-2">Selected Tools ({formData.tools.length})</h4>
          <div className="flex flex-wrap gap-2">
            {formData.tools.map(tool => (
              <span key={tool} className="px-3 py-1 bg-white border border-rose-200 rounded-full text-sm text-rose-600">
                {getToolIcon(tool)} {tool}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function VersionsTab({ versions, agentId, onRestore }) {
  const handleRestore = async (versionId) => {
    if (!confirm('Restore this version? This will create a new version with the restored configuration.')) return;

    try {
      await fetch(`/api/agents/${agentId}/restore`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ version_id: versionId })
      });
      onRestore();
    } catch (error) {
      console.error('Failed to restore version:', error);
    }
  };

  return (
    <div className="space-y-4">
      <p className="text-gray-500">View and restore previous versions of this agent.</p>

      {versions.length > 0 ? (
        <div className="space-y-3">
          {versions.map((version, index) => (
            <div
              key={version.id}
              className={`p-4 rounded-lg border ${
                version.is_latest || version.isLatest ? 'border-rose-200 bg-rose-50' : 'border-gray-200'
              }`}
            >
              <div className="flex items-center justify-between">
                <div>
                  <div className="flex items-center space-x-2">
                    <span className="font-medium text-gray-900">Version {version.version_number || version.versionNumber}</span>
                    {(version.is_latest || version.isLatest) && (
                      <span className="px-2 py-0.5 bg-rose-100 text-rose-600 text-xs rounded-full">Current</span>
                    )}
                  </div>
                  <p className="text-sm text-gray-500 mt-1">{version.change_summary || version.changeSummary}</p>
                  <p className="text-xs text-gray-400 mt-1">
                    {new Date(version.created_at || version.createdAt).toLocaleString()}
                  </p>
                </div>
                {!(version.is_latest || version.isLatest) && (
                  <button
                    onClick={() => handleRestore(version.id)}
                    className="px-3 py-1 text-sm text-rose-600 hover:bg-rose-100 rounded transition-colors"
                  >
                    Restore
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-8 text-gray-500">
          No version history available
        </div>
      )}
    </div>
  );
}

function CodeTab({ code }) {
  const copyToClipboard = () => {
    navigator.clipboard.writeText(code);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-gray-500">Generated Ruby code for this agent.</p>
        <button
          onClick={copyToClipboard}
          className="flex items-center space-x-1 px-3 py-1 text-sm text-gray-600 hover:text-rose-600 transition-colors"
        >
          <span>📋</span>
          <span>Copy</span>
        </button>
      </div>

      <pre className="p-4 bg-gray-900 text-gray-100 rounded-lg overflow-x-auto text-sm font-mono">
        <code>{code || 'Loading...'}</code>
      </pre>
    </div>
  );
}

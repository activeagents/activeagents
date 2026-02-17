import React, { useState } from 'react';
import AgentAvatar, { AGENT_PRESETS } from '../AgentAvatar';

const STEPS = [
  { id: 'basics', label: 'Basics', icon: '📝' },
  { id: 'appearance', label: 'Appearance', icon: '🎨' },
  { id: 'capabilities', label: 'Capabilities', icon: '🛠️' },
  { id: 'review', label: 'Review', icon: '✅' }
];

const PROVIDER_MODELS = {
  openai: ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'gpt-3.5-turbo'],
  anthropic: ['claude-sonnet-4-20250514', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229'],
  ollama: ['llama3', 'mistral', 'codellama', 'mixtral'],
  openrouter: ['openai/gpt-4o', 'anthropic/claude-sonnet-4-20250514', 'meta-llama/llama-3-70b-instruct']
};

export default function AgentBuilder({ meta, onSave, onCancel, isLoading }) {
  const [currentStep, setCurrentStep] = useState(0);
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    provider: 'openai',
    model: 'gpt-4o-mini',
    instructions: '',
    preset_type: 'terminal',
    appearance: {},
    instruction_sets: [],
    tools: [],
    model_config: {
      temperature: 0.7
    }
  });

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

  const selectPreset = (presetId) => {
    updateField('preset_type', presetId);
    // Apply preset appearance
    if (AGENT_PRESETS[presetId]) {
      updateField('appearance', AGENT_PRESETS[presetId]);
    }
  };

  const canProceed = () => {
    switch (currentStep) {
      case 0: return formData.name.trim().length >= 2;
      case 1: return true;
      case 2: return true;
      case 3: return true;
      default: return false;
    }
  };

  const handleSubmit = () => {
    onSave(formData);
  };

  const getAppearanceConfig = () => {
    const presetConfig = AGENT_PRESETS[formData.preset_type] || {};
    return { ...presetConfig, ...formData.appearance };
  };

  const renderStep = () => {
    switch (currentStep) {
      case 0:
        return <BasicsStep formData={formData} updateField={updateField} providerModels={PROVIDER_MODELS} />;
      case 1:
        return <AppearanceStep formData={formData} selectPreset={selectPreset} updateField={updateField} getAppearanceConfig={getAppearanceConfig} />;
      case 2:
        return <CapabilitiesStep formData={formData} meta={meta} toggleArrayItem={toggleArrayItem} updateField={updateField} />;
      case 3:
        return <ReviewStep formData={formData} getAppearanceConfig={getAppearanceConfig} />;
      default:
        return null;
    }
  };

  return (
    <div className="max-w-4xl mx-auto">
      {/* Progress Steps */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          {STEPS.map((step, index) => (
            <div key={step.id} className="flex items-center">
              <div
                className={`flex items-center justify-center w-10 h-10 rounded-full border-2 transition-colors ${
                  index < currentStep
                    ? 'bg-rose-500 border-rose-500 text-white'
                    : index === currentStep
                    ? 'border-rose-500 text-rose-500'
                    : 'border-gray-300 text-gray-400'
                }`}
              >
                {index < currentStep ? '✓' : step.icon}
              </div>
              <span className={`ml-2 text-sm font-medium ${
                index <= currentStep ? 'text-gray-900' : 'text-gray-400'
              }`}>
                {step.label}
              </span>
              {index < STEPS.length - 1 && (
                <div className={`w-16 h-0.5 mx-4 ${
                  index < currentStep ? 'bg-rose-500' : 'bg-gray-200'
                }`} />
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Step Content */}
      <div className="bg-white rounded-xl border border-gray-200 p-8">
        {renderStep()}
      </div>

      {/* Navigation */}
      <div className="flex justify-between mt-6">
        <button
          onClick={currentStep === 0 ? onCancel : () => setCurrentStep(currentStep - 1)}
          className="px-6 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition-colors"
        >
          {currentStep === 0 ? 'Cancel' : 'Back'}
        </button>

        <button
          onClick={currentStep === STEPS.length - 1 ? handleSubmit : () => setCurrentStep(currentStep + 1)}
          disabled={!canProceed() || isLoading}
          className={`px-6 py-2 rounded-lg transition-colors ${
            canProceed() && !isLoading
              ? 'bg-rose-500 text-white hover:bg-rose-600'
              : 'bg-gray-200 text-gray-400 cursor-not-allowed'
          }`}
        >
          {currentStep === STEPS.length - 1 ? 'Create Agent' : 'Continue'}
        </button>
      </div>
    </div>
  );
}

// Step 1: Basics
function BasicsStep({ formData, updateField, providerModels }) {
  return (
    <div className="space-y-6">
      <h2 className="text-xl font-semibold text-gray-900">Basic Information</h2>
      <p className="text-gray-500">Give your agent a name and configure its AI provider.</p>

      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Agent Name *</label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => updateField('name', e.target.value)}
            placeholder="My Awesome Agent"
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500 focus:border-transparent"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
          <textarea
            value={formData.description}
            onChange={(e) => updateField('description', e.target.value)}
            placeholder="What does this agent do?"
            rows={3}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500 focus:border-transparent"
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
              {Object.keys(providerModels).map(provider => (
                <option key={provider} value={provider}>
                  {provider.charAt(0).toUpperCase() + provider.slice(1)}
                </option>
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
              {providerModels[formData.provider].map(model => (
                <option key={model} value={model}>{model}</option>
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
          <div className="flex justify-between text-xs text-gray-400">
            <span>Precise</span>
            <span>Creative</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// Step 2: Appearance
function AppearanceStep({ formData, selectPreset, updateField, getAppearanceConfig }) {
  const presets = Object.keys(AGENT_PRESETS);
  const appearance = getAppearanceConfig();

  return (
    <div className="space-y-6">
      <h2 className="text-xl font-semibold text-gray-900">Agent Appearance</h2>
      <p className="text-gray-500">Choose a preset or customize your agent's look.</p>

      {/* Preview */}
      <div className="flex justify-center py-6 bg-gradient-to-br from-gray-50 to-gray-100 rounded-xl">
        <AgentAvatar
          hat={appearance.hat}
          hatAccessory={appearance.hatAccessory}
          heldItem={appearance.heldItem}
          size={150}
        />
      </div>

      {/* Preset Selection */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-3">Agent Type</label>
        <div className="grid grid-cols-5 gap-3">
          {presets.map(preset => (
            <button
              key={preset}
              onClick={() => selectPreset(preset)}
              className={`p-3 rounded-lg border-2 transition-all ${
                formData.preset_type === preset
                  ? 'border-rose-500 bg-rose-50'
                  : 'border-gray-200 hover:border-gray-300'
              }`}
            >
              <div className="flex flex-col items-center">
                <AgentAvatar {...AGENT_PRESETS[preset]} size={60} />
                <span className="text-xs mt-2 capitalize">{preset}</span>
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* Custom Options */}
      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Hat</label>
          <select
            value={appearance.hat || 'fedora'}
            onChange={(e) => updateField('appearance', { ...formData.appearance, hat: e.target.value })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg"
          >
            <option value="fedora">Fedora</option>
            <option value="safari">Safari</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Accessory</label>
          <select
            value={appearance.hatAccessory || ''}
            onChange={(e) => updateField('appearance', { ...formData.appearance, hatAccessory: e.target.value || null })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg"
          >
            <option value="">None</option>
            <option value="feather">Feather</option>
            <option value="cherryBlossom">Cherry Blossom</option>
            <option value="theaterMasks">Theater Masks</option>
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Held Item</label>
          <select
            value={appearance.heldItem || ''}
            onChange={(e) => updateField('appearance', { ...formData.appearance, heldItem: e.target.value || null })}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg"
          >
            <option value="">None</option>
            <option value="terminal">Terminal</option>
            <option value="browser">Browser</option>
            <option value="document">Document</option>
            <option value="scroll">Scroll</option>
            <option value="magnifyingGlass">Magnifying Glass</option>
          </select>
        </div>
      </div>
    </div>
  );
}

// Step 3: Capabilities
function CapabilitiesStep({ formData, meta, toggleArrayItem, updateField }) {
  return (
    <div className="space-y-6">
      <h2 className="text-xl font-semibold text-gray-900">Agent Capabilities</h2>
      <p className="text-gray-500">Configure instructions, tools, and system prompts.</p>

      {/* Instructions */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">System Instructions</label>
        <textarea
          value={formData.instructions}
          onChange={(e) => updateField('instructions', e.target.value)}
          placeholder="You are a helpful AI assistant that..."
          rows={5}
          className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500 focus:border-transparent font-mono text-sm"
        />
      </div>

      {/* Instruction Sets */}
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

      {/* Tools */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-3">Available Tools</label>
        <div className="grid grid-cols-4 gap-3">
          {meta.availableTools?.map(tool => (
            <button
              key={tool}
              onClick={() => toggleArrayItem('tools', tool)}
              className={`p-3 rounded-lg border-2 text-center transition-all ${
                formData.tools.includes(tool)
                  ? 'border-rose-500 bg-rose-50 text-rose-700'
                  : 'border-gray-200 hover:border-gray-300 text-gray-700'
              }`}
            >
              <span className="text-xl block mb-1">
                {getToolIcon(tool)}
              </span>
              <span className="text-xs capitalize">{tool}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

// Step 4: Review
function ReviewStep({ formData, getAppearanceConfig }) {
  const appearance = getAppearanceConfig();

  return (
    <div className="space-y-6">
      <h2 className="text-xl font-semibold text-gray-900">Review Your Agent</h2>
      <p className="text-gray-500">Confirm the configuration before creating your agent.</p>

      <div className="grid grid-cols-2 gap-8">
        {/* Preview */}
        <div className="flex flex-col items-center py-6 bg-gradient-to-br from-gray-50 to-gray-100 rounded-xl">
          <AgentAvatar
            hat={appearance.hat}
            hatAccessory={appearance.hatAccessory}
            heldItem={appearance.heldItem}
            size={120}
          />
          <h3 className="mt-4 text-lg font-semibold text-gray-900">{formData.name}</h3>
          <p className="text-sm text-gray-500">{formData.description || 'No description'}</p>
        </div>

        {/* Details */}
        <div className="space-y-4">
          <div>
            <span className="text-sm font-medium text-gray-500">Provider / Model</span>
            <p className="text-gray-900">{formData.provider} / {formData.model}</p>
          </div>

          <div>
            <span className="text-sm font-medium text-gray-500">Temperature</span>
            <p className="text-gray-900">{formData.model_config.temperature}</p>
          </div>

          <div>
            <span className="text-sm font-medium text-gray-500">Instruction Sets</span>
            <div className="flex flex-wrap gap-1 mt-1">
              {formData.instruction_sets.length > 0 ? (
                formData.instruction_sets.map(i => (
                  <span key={i} className="px-2 py-0.5 bg-gray-100 rounded text-xs">{i}</span>
                ))
              ) : (
                <span className="text-gray-400 text-sm">None selected</span>
              )}
            </div>
          </div>

          <div>
            <span className="text-sm font-medium text-gray-500">Tools</span>
            <div className="flex flex-wrap gap-1 mt-1">
              {formData.tools.length > 0 ? (
                formData.tools.map(t => (
                  <span key={t} className="px-2 py-0.5 bg-rose-100 text-rose-700 rounded text-xs">{t}</span>
                ))
              ) : (
                <span className="text-gray-400 text-sm">None selected</span>
              )}
            </div>
          </div>
        </div>
      </div>

      {formData.instructions && (
        <div>
          <span className="text-sm font-medium text-gray-500">System Instructions</span>
          <pre className="mt-2 p-4 bg-gray-50 rounded-lg text-sm text-gray-700 whitespace-pre-wrap font-mono">
            {formData.instructions}
          </pre>
        </div>
      )}
    </div>
  );
}

function getToolIcon(tool) {
  const icons = {
    terminal: '💻',
    playwright: '🎭',
    filesystem: '📁',
    code: '📝',
    database: '🗄️',
    slack: '💬',
    fetch: '🌐',
    search: '🔍',
    edit: '✏️',
    translate: '🌍',
    memory: '🧠'
  };
  return icons[tool] || '🔧';
}

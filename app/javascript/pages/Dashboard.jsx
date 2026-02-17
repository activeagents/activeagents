import React, { useState, useEffect } from 'react';
import AgentList from '../components/dashboard/AgentList';
import AgentBuilder from '../components/dashboard/AgentBuilder';
import AgentEditor from '../components/dashboard/AgentEditor';
import AgentRunner from '../components/dashboard/AgentRunner';
import Sidebar from '../components/dashboard/Sidebar';
import Header from '../components/dashboard/Header';

/**
 * Dashboard - Main dashboard application
 *
 * Routes are handled client-side for SPA-like experience
 * Real routes still go through Rails/Inertia for SSR benefits
 */
export default function Dashboard({ user, initialAgents = [], meta = {} }) {
  const [agents, setAgents] = useState(initialAgents);
  const [currentView, setCurrentView] = useState('list'); // list, builder, editor, runner
  const [selectedAgent, setSelectedAgent] = useState(null);
  const [isLoading, setIsLoading] = useState(false);
  const [notification, setNotification] = useState(null);

  // Parse URL to determine initial view
  useEffect(() => {
    const path = window.location.pathname;
    if (path.includes('/agents/new')) {
      setCurrentView('builder');
    } else if (path.match(/\/agents\/\d+\/edit/)) {
      const id = path.match(/\/agents\/(\d+)/)?.[1];
      if (id) loadAgent(id, 'editor');
    } else if (path.match(/\/agents\/\d+\/run/)) {
      const id = path.match(/\/agents\/(\d+)/)?.[1];
      if (id) loadAgent(id, 'runner');
    }
  }, []);

  const loadAgent = async (id, view) => {
    setIsLoading(true);
    try {
      const response = await fetch(`/api/agents/${id}`);
      const data = await response.json();
      setSelectedAgent(data.agent);
      setCurrentView(view);
    } catch (error) {
      showNotification('Failed to load agent', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const refreshAgents = async () => {
    setIsLoading(true);
    try {
      const response = await fetch('/api/agents');
      const data = await response.json();
      setAgents(data.agents);
    } catch (error) {
      showNotification('Failed to refresh agents', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const showNotification = (message, type = 'info') => {
    setNotification({ message, type });
    setTimeout(() => setNotification(null), 3000);
  };

  const handleCreateAgent = async (agentData) => {
    setIsLoading(true);
    try {
      const response = await fetch('/api/agents', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ agent: agentData })
      });

      if (response.ok) {
        const data = await response.json();
        setAgents([data.agent, ...agents]);
        setSelectedAgent(data.agent);
        setCurrentView('editor');
        showNotification('Agent created successfully!', 'success');
        window.history.pushState({}, '', `/dashboard/agents/${data.agent.id}/edit`);
      } else {
        const error = await response.json();
        showNotification(error.errors?.join(', ') || 'Failed to create agent', 'error');
      }
    } catch (error) {
      showNotification('Failed to create agent', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const handleUpdateAgent = async (id, agentData) => {
    setIsLoading(true);
    try {
      const response = await fetch(`/api/agents/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ agent: agentData })
      });

      if (response.ok) {
        const data = await response.json();
        setAgents(agents.map(a => a.id === id ? data.agent : a));
        setSelectedAgent(data.agent);
        showNotification('Agent updated!', 'success');
      } else {
        const error = await response.json();
        showNotification(error.errors?.join(', ') || 'Failed to update agent', 'error');
      }
    } catch (error) {
      showNotification('Failed to update agent', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const handleDeleteAgent = async (id) => {
    if (!confirm('Are you sure you want to delete this agent?')) return;

    setIsLoading(true);
    try {
      const response = await fetch(`/api/agents/${id}`, { method: 'DELETE' });

      if (response.ok) {
        setAgents(agents.filter(a => a.id !== id));
        setSelectedAgent(null);
        setCurrentView('list');
        showNotification('Agent deleted', 'success');
        window.history.pushState({}, '', '/dashboard');
      }
    } catch (error) {
      showNotification('Failed to delete agent', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const handleDuplicateAgent = async (id) => {
    setIsLoading(true);
    try {
      const response = await fetch(`/api/agents/${id}/duplicate`, { method: 'POST' });

      if (response.ok) {
        const data = await response.json();
        setAgents([data.agent, ...agents]);
        showNotification('Agent duplicated!', 'success');
      }
    } catch (error) {
      showNotification('Failed to duplicate agent', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const navigateTo = (view, agent = null) => {
    setSelectedAgent(agent);
    setCurrentView(view);

    // Update URL
    let path = '/dashboard';
    if (view === 'builder') path = '/dashboard/agents/new';
    else if (view === 'editor' && agent) path = `/dashboard/agents/${agent.id}/edit`;
    else if (view === 'runner' && agent) path = `/dashboard/agents/${agent.id}/run`;

    window.history.pushState({}, '', path);
  };

  const renderContent = () => {
    switch (currentView) {
      case 'builder':
        return (
          <AgentBuilder
            meta={meta}
            onSave={handleCreateAgent}
            onCancel={() => navigateTo('list')}
            isLoading={isLoading}
          />
        );
      case 'editor':
        return selectedAgent ? (
          <AgentEditor
            agent={selectedAgent}
            meta={meta}
            onSave={(data) => handleUpdateAgent(selectedAgent.id, data)}
            onDelete={() => handleDeleteAgent(selectedAgent.id)}
            onRun={() => navigateTo('runner', selectedAgent)}
            onBack={() => navigateTo('list')}
            isLoading={isLoading}
          />
        ) : null;
      case 'runner':
        return selectedAgent ? (
          <AgentRunner
            agent={selectedAgent}
            onBack={() => navigateTo('editor', selectedAgent)}
          />
        ) : null;
      default:
        return (
          <AgentList
            agents={agents}
            meta={meta}
            onSelect={(agent) => navigateTo('editor', agent)}
            onNew={() => navigateTo('builder')}
            onDuplicate={handleDuplicateAgent}
            onDelete={handleDeleteAgent}
            onRefresh={refreshAgents}
            isLoading={isLoading}
          />
        );
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 flex">
      <Sidebar
        currentView={currentView}
        onNavigate={navigateTo}
        agentCount={agents.length}
      />

      <div className="flex-1 flex flex-col">
        <Header
          user={user}
          currentView={currentView}
          selectedAgent={selectedAgent}
        />

        <main className="flex-1 p-6 overflow-auto">
          {renderContent()}
        </main>
      </div>

      {/* Notification Toast */}
      {notification && (
        <div className={`fixed bottom-4 right-4 px-6 py-3 rounded-lg shadow-lg transition-all transform ${
          notification.type === 'error' ? 'bg-red-500' :
          notification.type === 'success' ? 'bg-green-500' : 'bg-blue-500'
        } text-white`}>
          {notification.message}
        </div>
      )}

      {/* Loading Overlay */}
      {isLoading && (
        <div className="fixed inset-0 bg-black bg-opacity-20 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg p-4 shadow-xl">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-rose-500"></div>
          </div>
        </div>
      )}
    </div>
  );
}

import React, { useState, useEffect } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

// Mock data matching the lander preview design
const MOCK_EVALUATIONS = [
  {
    id: 'eval-001',
    name: 'Translation Quality',
    agent: 'TranslationAgent',
    created_at: new Date(Date.now() - 120000).toISOString(),
    model_judge: 'claude-3-haiku',
    criteria: ['semantic_similarity', 'grammar', 'tone'],
    samples: { passed: 50, total: 50 },
    scores: [
      { label: 'Accuracy', value: 0.94, status: 'high' },
      { label: 'Fluency', value: 0.88, status: 'high' },
      { label: 'Faithfulness', value: 0.72, status: 'medium', warning: 'Below threshold (0.80)' },
    ],
  },
  {
    id: 'eval-002',
    name: 'Code Review Accuracy',
    agent: 'CodeReviewAgent',
    created_at: new Date(Date.now() - 3600000).toISOString(),
    model_judge: 'gpt-4o',
    criteria: ['bug_detection', 'suggestion_quality', 'clarity'],
    samples: { passed: 47, total: 50 },
    scores: [
      { label: 'Bug Detection', value: 0.91, status: 'high' },
      { label: 'Suggestion Quality', value: 0.86, status: 'high' },
      { label: 'Clarity', value: 0.89, status: 'high' },
    ],
  },
  {
    id: 'eval-003',
    name: 'Documentation Completeness',
    agent: 'DocumentationAgent',
    created_at: new Date(Date.now() - 7200000).toISOString(),
    model_judge: 'claude-3-haiku',
    criteria: ['coverage', 'accuracy', 'readability'],
    samples: { passed: 42, total: 50 },
    scores: [
      { label: 'Coverage', value: 0.78, status: 'medium', warning: 'Could improve coverage' },
      { label: 'Accuracy', value: 0.92, status: 'high' },
      { label: 'Readability', value: 0.85, status: 'high' },
    ],
  },
];

export default function EvaluationsView() {
  const { darkMode } = useTheme();
  const [evaluations, setEvaluations] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [expandedEval, setExpandedEval] = useState(null);
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    setTimeout(() => {
      setEvaluations(MOCK_EVALUATIONS);
      setIsLoading(false);
      setExpandedEval(MOCK_EVALUATIONS[0]?.id);
    }, 500);
  }, []);

  const formatTime = (dateStr) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 60) return `${diffMins} min ago`;
    if (diffMins < 1440) return `${Math.floor(diffMins / 60)} hours ago`;
    return `${Math.floor(diffMins / 1440)} days ago`;
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  const avgAllScores = evaluations.flatMap(e => e.scores).reduce((sum, s) => sum + s.value, 0) /
    evaluations.flatMap(e => e.scores).length;

  const getScoreColor = (value, mode = 'dark') => {
    if (value >= 0.85) return mode === 'dark' ? '#22c55e' : 'text-green-600';
    if (value >= 0.70) return mode === 'dark' ? '#eab308' : 'text-yellow-600';
    return mode === 'dark' ? '#ef4444' : 'text-red-600';
  };

  // Light mode version
  if (!darkMode) {
    return (
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Evaluations</h1>
            <p className="text-sm text-gray-500 mt-1">Score outputs with LLM-as-judge, rule-based checks, or custom criteria</p>
          </div>
          <div className="flex items-center gap-3">
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              className="px-3 py-2 bg-white border border-gray-300 rounded-lg text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-red-500"
            >
              <option value="all">All Evaluations</option>
              <option value="passing">Passing</option>
              <option value="failing">Failing</option>
            </select>
            <button className="px-4 py-2 bg-red-500 text-white rounded-lg text-sm font-medium hover:bg-red-600 transition-colors">
              New Evaluation
            </button>
          </div>
        </div>

        {/* Summary Stats */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-white rounded-xl p-5 border border-gray-200 shadow-sm">
            <div className="text-sm text-gray-500 mb-1">Total Evaluations</div>
            <div className="text-3xl font-bold text-gray-900">{evaluations.length}</div>
          </div>
          <div className="bg-white rounded-xl p-5 border border-gray-200 shadow-sm">
            <div className="text-sm text-gray-500 mb-1">Average Score</div>
            <div className={`text-3xl font-bold ${avgAllScores >= 0.85 ? 'text-green-600' : avgAllScores >= 0.70 ? 'text-yellow-600' : 'text-red-600'}`}>
              {(avgAllScores * 100).toFixed(0)}%
            </div>
          </div>
          <div className="bg-white rounded-xl p-5 border border-gray-200 shadow-sm">
            <div className="text-sm text-gray-500 mb-1">Samples Evaluated</div>
            <div className="text-3xl font-bold text-gray-900">
              {evaluations.reduce((sum, e) => sum + e.samples.total, 0)}
            </div>
          </div>
        </div>

        {/* Evaluations List */}
        <div className="space-y-4">
          {evaluations.map((evaluation) => (
            <div key={evaluation.id} className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
              <div
                className="flex items-center justify-between p-4 cursor-pointer hover:bg-gray-50"
                onClick={() => setExpandedEval(expandedEval === evaluation.id ? null : evaluation.id)}
              >
                <div className="flex items-center gap-3">
                  <span className="px-2 py-1 text-xs font-medium bg-purple-100 text-purple-700 rounded">EVALUATION</span>
                  <span className="font-medium text-gray-900">{evaluation.name}</span>
                </div>
                <span className="text-sm text-gray-500">{formatTime(evaluation.created_at)}</span>
              </div>

              {expandedEval === evaluation.id && (
                <div className="border-t border-gray-200">
                  {/* Scores */}
                  <div className="p-4 space-y-3">
                    {evaluation.scores.map((score) => (
                      <div key={score.label} className="flex items-center gap-4">
                        <div className="w-24 text-sm text-gray-600">{score.label}</div>
                        <div className="flex-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                          <div
                            className={`h-full rounded-full transition-all ${
                              score.status === 'high' ? 'bg-green-500' :
                              score.status === 'medium' ? 'bg-yellow-500' : 'bg-red-500'
                            }`}
                            style={{ width: `${score.value * 100}%` }}
                          />
                        </div>
                        <div className={`w-12 text-sm font-medium text-right ${
                          score.status === 'high' ? 'text-green-600' :
                          score.status === 'medium' ? 'text-yellow-600' : 'text-red-600'
                        }`}>
                          {score.value.toFixed(2)}
                        </div>
                      </div>
                    ))}
                  </div>

                  {/* Details */}
                  <div className="p-4 bg-gray-50 grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                    <div>
                      <div className="text-gray-500">Model Judge</div>
                      <div className="font-medium text-gray-900">{evaluation.model_judge}</div>
                    </div>
                    <div>
                      <div className="text-gray-500">Criteria</div>
                      <div className="font-medium text-gray-900">{evaluation.criteria.join(', ')}</div>
                    </div>
                    <div>
                      <div className="text-gray-500">Samples</div>
                      <div className="font-medium text-gray-900">{evaluation.samples.passed} / {evaluation.samples.total} passed</div>
                    </div>
                    <div>
                      <div className="text-gray-500">Agent</div>
                      <div className="font-medium text-gray-900">{evaluation.agent}</div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>

        {evaluations.length === 0 && (
          <div className="text-center py-12 bg-white rounded-xl border border-gray-200">
            <div className="text-gray-500 text-lg">No evaluations yet</div>
            <p className="text-gray-400 text-sm mt-2">Create an evaluation to start scoring agent outputs</p>
          </div>
        )}
      </div>
    );
  }

  // Dark mode version
  return (
    <div className="preview-content" style={{ borderRadius: '12px', overflow: 'hidden', minHeight: 'calc(100vh - 200px)' }}>
      {/* Header inside dark container */}
      <div style={{ padding: '24px 24px 0 24px', borderBottom: '1px solid rgba(255,255,255,0.1)', marginBottom: '16px', paddingBottom: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <h1 style={{ fontSize: '24px', fontWeight: 'bold', color: 'white', margin: 0 }}>Evaluations</h1>
            <p style={{ fontSize: '14px', color: 'rgba(255,255,255,0.6)', marginTop: '4px' }}>Score outputs with LLM-as-judge, rule-based checks, or custom criteria</p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <select
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              style={{
                padding: '8px 12px',
                background: 'rgba(255,255,255,0.1)',
                border: '1px solid rgba(255,255,255,0.2)',
                borderRadius: '8px',
                color: 'white',
                fontSize: '14px'
              }}
            >
              <option value="all">All Evaluations</option>
              <option value="passing">Passing</option>
              <option value="failing">Failing</option>
            </select>
            <button style={{
              padding: '8px 16px',
              background: '#ef4444',
              color: 'white',
              borderRadius: '8px',
              border: 'none',
              fontSize: '14px',
              fontWeight: '500',
              cursor: 'pointer'
            }}>
              New Evaluation
            </button>
          </div>
        </div>
      </div>

      {/* Summary Stats - Dark themed */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', padding: '0 24px 24px 24px' }}>
        <div style={{
          background: 'rgba(255,255,255,0.05)',
          borderRadius: '12px',
          padding: '20px',
          border: '1px solid rgba(255,255,255,0.1)'
        }}>
          <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>Total Evaluations</div>
          <div style={{ fontSize: '32px', fontWeight: 'bold', color: 'white' }}>{evaluations.length}</div>
        </div>
        <div style={{
          background: 'rgba(255,255,255,0.05)',
          borderRadius: '12px',
          padding: '20px',
          border: '1px solid rgba(255,255,255,0.1)'
        }}>
          <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>Average Score</div>
          <div style={{
            fontSize: '32px',
            fontWeight: 'bold',
            color: avgAllScores >= 0.85 ? '#22c55e' : avgAllScores >= 0.70 ? '#eab308' : '#ef4444'
          }}>
            {(avgAllScores * 100).toFixed(0)}%
          </div>
        </div>
        <div style={{
          background: 'rgba(255,255,255,0.05)',
          borderRadius: '12px',
          padding: '20px',
          border: '1px solid rgba(255,255,255,0.1)'
        }}>
          <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>Samples Evaluated</div>
          <div style={{ fontSize: '32px', fontWeight: 'bold', color: 'white' }}>
            {evaluations.reduce((sum, e) => sum + e.samples.total, 0)}
          </div>
        </div>
      </div>

      {/* Evaluations List */}
      {evaluations.map((evaluation) => (
        <div key={evaluation.id} className="preview-evaluation">
          <div
            className="eval-header"
            onClick={() => setExpandedEval(expandedEval === evaluation.id ? null : evaluation.id)}
            style={{ cursor: 'pointer' }}
          >
            <span className="eval-badge">EVALUATION</span>
            <span className="eval-name">{evaluation.name}</span>
            <span className="eval-time">{formatTime(evaluation.created_at)}</span>
          </div>

          {expandedEval === evaluation.id && (
            <>
              <div className="eval-scores">
                {evaluation.scores.map((score) => (
                  <div key={score.label} className="score-item">
                    <div className="score-label">{score.label}</div>
                    <div className="score-bar-container">
                      <div
                        className={`score-bar ${score.status} animated`}
                        style={{ width: `${score.value * 100}%` }}
                      ></div>
                    </div>
                    <div className={`score-value ${score.status}`}>{score.value.toFixed(2)}</div>
                  </div>
                ))}
              </div>

              <div className="eval-details">
                <div className="eval-row">
                  <span className="eval-key">Model Judge</span>
                  <span className="eval-val">{evaluation.model_judge}</span>
                </div>
                <div className="eval-row">
                  <span className="eval-key">Criteria</span>
                  <span className="eval-val">{evaluation.criteria.join(', ')}</span>
                </div>
                <div className="eval-row">
                  <span className="eval-key">Samples</span>
                  <span className="eval-val">{evaluation.samples.passed} / {evaluation.samples.total} passed</span>
                </div>
                <div className="eval-row">
                  <span className="eval-key">Agent</span>
                  <span className="eval-val">{evaluation.agent}</span>
                </div>
              </div>
            </>
          )}
        </div>
      ))}

      {evaluations.length === 0 && (
        <div style={{ textAlign: 'center', padding: '48px 0' }}>
          <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: '18px' }}>No evaluations yet</div>
          <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: '14px', marginTop: '8px' }}>Create an evaluation to start scoring agent outputs</p>
        </div>
      )}
    </div>
  );
}

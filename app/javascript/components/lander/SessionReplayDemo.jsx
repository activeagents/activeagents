import React, { useState, useEffect, useCallback, useRef } from 'react';

/**
 * SessionReplayDemo - Interactive demo for the landing page
 *
 * Shows a pre-recorded agent session with the ability to:
 * 1. Watch the agent automate browser tasks
 * 2. Take over from where the agent stopped
 * 3. See user interactions tracked in trace analytics
 */

const DEMO_ACTIONS = [
  { id: 1, type: 'navigate', value: 'checkout.stripe.com', timestamp_ms: 0, status: 'completed' },
  { id: 2, type: 'snapshot', value: 'initial load', timestamp_ms: 500, status: 'completed' },
  { id: 3, type: 'type', selector: '#card-input', value: '4242 4242 4242 4242', timestamp_ms: 1500, status: 'completed' },
  { id: 4, type: 'type', selector: '#expiry-input', value: '12/25', timestamp_ms: 4000, status: 'active' },
  { id: 5, type: 'type', selector: '#cvc-input', value: '123', timestamp_ms: 5500, status: 'pending' },
  { id: 6, type: 'click', selector: '#pay-btn', value: 'Pay $99.00', timestamp_ms: 7000, status: 'pending' },
  { id: 7, type: 'snapshot', value: 'payment complete', timestamp_ms: 8500, status: 'pending' },
];

const ACTION_ICONS = {
  navigate: 'fa-globe',
  snapshot: 'fa-camera',
  type: 'fa-keyboard',
  click: 'fa-hand-pointer',
  form_fill: 'fa-align-left',
};

export default function SessionReplayDemo({ onTakeOver }) {
  const [actions, setActions] = useState(DEMO_ACTIONS);
  const [currentActionIndex, setCurrentActionIndex] = useState(2);
  const [isPlaying, setIsPlaying] = useState(true);
  const [isPaused, setIsPaused] = useState(false);
  const [formValues, setFormValues] = useState({
    card: '',
    expiry: '',
    cvc: ''
  });
  const [paymentStatus, setPaymentStatus] = useState('ready'); // ready, processing, success
  const [showHandoffPrompt, setShowHandoffPrompt] = useState(false);
  const [userHasTakenOver, setUserHasTakenOver] = useState(false);
  const [traceLog, setTraceLog] = useState([]);

  const viewportRef = useRef(null);
  const cursorRef = useRef(null);
  const playbackTimer = useRef(null);

  // Cursor positions for each action
  const cursorPositions = {
    'card': { top: '35%', left: '50%' },
    'expiry': { top: '52%', left: '30%' },
    'cvc': { top: '52%', left: '70%' },
    'pay': { top: '75%', left: '50%' },
  };

  // Simulate typing animation
  const typeText = useCallback((text, field, callback) => {
    let i = formValues[field].length;

    const typeChar = () => {
      if (isPaused || userHasTakenOver) return;

      if (i < text.length) {
        setFormValues(prev => ({
          ...prev,
          [field]: text.substring(0, i + 1)
        }));
        i++;
        playbackTimer.current = setTimeout(typeChar, 60 + Math.random() * 40);
      } else {
        callback?.();
      }
    };

    typeChar();
  }, [formValues, isPaused, userHasTakenOver]);

  // Run playback animation
  useEffect(() => {
    if (!isPlaying || isPaused || userHasTakenOver) return;

    const currentAction = actions[currentActionIndex];
    if (!currentAction || currentAction.status === 'pending') {
      // Reached handoff point
      setShowHandoffPrompt(true);
      setIsPlaying(false);
      return;
    }

    const runAction = () => {
      switch (currentAction.type) {
        case 'type':
          if (currentAction.selector === '#card-input') {
            typeText('4242 4242 4242 4242', 'card', () => {
              updateActionStatus(currentActionIndex, 'completed');
              setCurrentActionIndex(prev => prev + 1);
            });
          } else if (currentAction.selector === '#expiry-input') {
            typeText('12/25', 'expiry', () => {
              updateActionStatus(currentActionIndex, 'completed');
              setCurrentActionIndex(prev => prev + 1);
            });
          } else if (currentAction.selector === '#cvc-input') {
            typeText('123', 'cvc', () => {
              updateActionStatus(currentActionIndex, 'completed');
              setCurrentActionIndex(prev => prev + 1);
            });
          }
          break;

        case 'click':
          setPaymentStatus('processing');
          setTimeout(() => {
            setPaymentStatus('success');
            updateActionStatus(currentActionIndex, 'completed');
            setCurrentActionIndex(prev => prev + 1);
          }, 1500);
          break;

        default:
          updateActionStatus(currentActionIndex, 'completed');
          playbackTimer.current = setTimeout(() => {
            setCurrentActionIndex(prev => prev + 1);
          }, 500);
      }
    };

    // Set active status
    updateActionStatus(currentActionIndex, 'active');

    // Delay before running action
    playbackTimer.current = setTimeout(runAction, 600);

    return () => {
      if (playbackTimer.current) {
        clearTimeout(playbackTimer.current);
      }
    };
  }, [currentActionIndex, isPlaying, isPaused, userHasTakenOver]);

  const updateActionStatus = (index, status) => {
    setActions(prev => prev.map((action, i) =>
      i === index ? { ...action, status } : action
    ));
  };

  // Handle user taking over
  const handleTakeOver = () => {
    setUserHasTakenOver(true);
    setShowHandoffPrompt(false);
    setIsPlaying(false);

    // Log handoff to trace
    addTraceEntry({
      type: 'handoff',
      message: 'User took over session',
      timestamp: new Date().toISOString(),
    });

    if (onTakeOver) {
      onTakeOver({
        formValues,
        currentAction: actions[currentActionIndex],
        remainingActions: actions.slice(currentActionIndex),
      });
    }
  };

  // Track user interactions after handoff
  const handleUserInput = (field, value) => {
    setFormValues(prev => ({ ...prev, [field]: value }));

    if (userHasTakenOver) {
      addTraceEntry({
        type: 'user_input',
        field,
        value: value.replace(/\d/g, '*'), // Mask sensitive data
        timestamp: new Date().toISOString(),
      });
    }
  };

  const handleUserPayment = () => {
    setPaymentStatus('processing');

    addTraceEntry({
      type: 'user_action',
      action: 'click',
      selector: '#pay-btn',
      timestamp: new Date().toISOString(),
    });

    setTimeout(() => {
      setPaymentStatus('success');
      addTraceEntry({
        type: 'completion',
        message: 'Payment successful',
        timestamp: new Date().toISOString(),
      });
    }, 1500);
  };

  const addTraceEntry = (entry) => {
    setTraceLog(prev => [...prev.slice(-4), entry]); // Keep last 5 entries
  };

  // Cursor position based on current action
  const getCursorPosition = () => {
    const action = actions[currentActionIndex];
    if (!action) return cursorPositions.card;

    if (action.selector === '#card-input') return cursorPositions.card;
    if (action.selector === '#expiry-input') return cursorPositions.expiry;
    if (action.selector === '#cvc-input') return cursorPositions.cvc;
    if (action.selector === '#pay-btn') return cursorPositions.pay;

    return cursorPositions.card;
  };

  const progress = (currentActionIndex / (actions.length - 1)) * 100;

  return (
    <div className="preview-replay" id="session-replay-container">
      {/* Browser Chrome */}
      <div className="replay-browser">
        <div className="browser-chrome">
          <div className="browser-dots">
            <span className="dot"></span>
            <span className="dot"></span>
            <span className="dot"></span>
          </div>
          <div className="browser-address">
            <i className="fa-solid fa-lock"></i>
            <span className="address-text">checkout.stripe.com/pay/cs_test_...</span>
          </div>
          <div className="cassette-badge">
            <i className={`fa-solid fa-circle ${isPlaying && !isPaused ? 'recording' : ''}`}></i>
            <span>{userHasTakenOver ? 'LIVE' : isPlaying ? 'REC' : 'PAUSED'}</span>
          </div>
        </div>

        {/* Viewport */}
        <div
          ref={viewportRef}
          className="browser-viewport"
          onMouseEnter={() => !userHasTakenOver && setIsPaused(true)}
          onMouseLeave={() => !userHasTakenOver && setIsPaused(false)}
        >
          <div className="page-content checkout-page">
            <div className="checkout-form">
              <div className="form-section">
                <div className="form-label">Card number</div>
                <div className={`form-input card-field ${currentActionIndex === 2 ? 'typing' : ''}`}>
                  <span className="card-icon"><i className="fa-brands fa-cc-visa"></i></span>
                  <input
                    type="text"
                    className="checkout-input"
                    value={formValues.card}
                    onChange={(e) => handleUserInput('card', e.target.value)}
                    placeholder="4242 4242 4242 4242"
                    disabled={!userHasTakenOver && isPlaying}
                  />
                </div>
              </div>

              <div className="form-row">
                <div className="form-section half">
                  <div className="form-label">Expiry</div>
                  <div className={`form-input expiry-field ${currentActionIndex === 3 ? 'typing' : ''}`}>
                    <input
                      type="text"
                      className="checkout-input"
                      value={formValues.expiry}
                      onChange={(e) => handleUserInput('expiry', e.target.value)}
                      placeholder="MM/YY"
                      disabled={!userHasTakenOver && isPlaying}
                    />
                  </div>
                </div>
                <div className="form-section half">
                  <div className="form-label">CVC</div>
                  <div className={`form-input cvc-field ${currentActionIndex === 4 ? 'typing' : ''}`}>
                    <input
                      type="text"
                      className="checkout-input"
                      value={formValues.cvc}
                      onChange={(e) => handleUserInput('cvc', e.target.value)}
                      placeholder="123"
                      disabled={!userHasTakenOver && isPlaying}
                    />
                  </div>
                </div>
              </div>

              <button
                className="checkout-btn"
                onClick={userHasTakenOver ? handleUserPayment : undefined}
                style={{
                  background: paymentStatus === 'success'
                    ? 'linear-gradient(135deg, #10b981, #059669)'
                    : undefined,
                  opacity: paymentStatus === 'processing' ? 0.7 : 1,
                }}
                disabled={!userHasTakenOver || paymentStatus === 'processing'}
              >
                {paymentStatus === 'processing' ? 'Processing...' :
                  paymentStatus === 'success' ? 'Payment Successful!' : 'Pay $99.00'}
              </button>
            </div>
          </div>

          {/* Agent Cursor - hidden after handoff */}
          {!userHasTakenOver && (
            <div
              ref={cursorRef}
              className={`agent-cursor ${isPaused ? 'paused' : ''}`}
              style={getCursorPosition()}
            >
              <svg className="cursor-icon" viewBox="0 0 24 24" fill="currentColor">
                <path d="M4 4l16 8-7 2-2 7z"/>
              </svg>
              <span className="cursor-label">Agent</span>
            </div>
          )}

          {/* Handoff Prompt */}
          {showHandoffPrompt && (
            <div className="handoff-overlay">
              <div className="handoff-prompt">
                <h3>Agent paused at step {currentActionIndex + 1}</h3>
                <p>Take over and complete the checkout yourself!</p>
                <button className="handoff-btn" onClick={handleTakeOver}>
                  <i className="fa-solid fa-hand"></i> Take Over Session
                </button>
                <p className="handoff-hint">Your actions will be tracked in the trace log</p>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Sidebar */}
      <div className="replay-sidebar">
        <div className="sidebar-header">
          <span className="cassette-icon"><i className="fa-solid fa-tape"></i></span>
          <span className="cassette-name">checkout_flow.vcr</span>
        </div>

        <div className="action-list">
          {actions.map((action, idx) => (
            <div
              key={action.id}
              className={`action-item ${action.status}`}
              onClick={() => {
                if (!userHasTakenOver) {
                  setCurrentActionIndex(idx);
                }
              }}
            >
              <span className="action-icon">
                <i className={`fa-solid ${ACTION_ICONS[action.type] || 'fa-circle'}`}></i>
              </span>
              <span className="action-text">
                {action.type === 'type' ? `type ${action.selector?.replace('#', '').replace('-input', '')}` :
                  action.type === 'click' ? `click ${action.value}` :
                    action.type}
              </span>
              <span className="action-status">
                {action.status === 'completed' && <i className="fa-solid fa-check"></i>}
                {action.status === 'active' && <i className="fa-solid fa-play"></i>}
              </span>
            </div>
          ))}
        </div>

        {/* Trace Log - shows user interactions after handoff */}
        {userHasTakenOver && traceLog.length > 0 && (
          <div className="trace-log">
            <div className="trace-log-header">
              <i className="fa-solid fa-wave-square"></i> Trace Log
            </div>
            {traceLog.map((entry, idx) => (
              <div key={idx} className={`trace-entry ${entry.type}`}>
                <span className="trace-type">{entry.type}</span>
                <span className="trace-message">
                  {entry.message || `${entry.action || entry.field}: ${entry.value || ''}`}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Playback Controls */}
      <div className="replay-controls">
        <div className="replay-timeline">
          <div className="timeline-track">
            <div className="timeline-progress" style={{ width: `${progress}%` }}></div>
            <div className="timeline-snapshots">
              {actions.filter(a => a.type === 'snapshot').map((action, idx) => {
                const position = (actions.indexOf(action) / (actions.length - 1)) * 100;
                return (
                  <span
                    key={idx}
                    className={`snapshot-marker ${action.status}`}
                    style={{ left: `${position}%` }}
                    title={action.value}
                  >
                    <i className="fa-solid fa-camera"></i>
                  </span>
                );
              })}
            </div>
            <div className="timeline-playhead" style={{ left: `${progress}%` }}></div>
          </div>
        </div>
        <div className="replay-buttons">
          <button
            className="replay-btn"
            onClick={() => setCurrentActionIndex(prev => Math.max(0, prev - 1))}
            disabled={userHasTakenOver}
          >
            <i className="fa-solid fa-backward-step"></i>
          </button>
          <button
            className="replay-btn play-btn"
            onClick={() => setIsPlaying(!isPlaying)}
            disabled={userHasTakenOver}
          >
            <i className={`fa-solid ${isPlaying && !isPaused ? 'fa-pause' : 'fa-play'}`}></i>
          </button>
          <button
            className="replay-btn"
            onClick={() => setCurrentActionIndex(prev => Math.min(actions.length - 1, prev + 1))}
            disabled={userHasTakenOver}
          >
            <i className="fa-solid fa-forward-step"></i>
          </button>
          <span className="replay-speed">1x</span>
          <span className="replay-time">
            {userHasTakenOver ? 'Your session' : `Step ${currentActionIndex + 1}/${actions.length}`}
          </span>
        </div>
      </div>

      <style jsx>{`
        .handoff-overlay {
          position: absolute;
          inset: 0;
          background: rgba(0, 0, 0, 0.75);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 100;
        }

        .handoff-prompt {
          background: linear-gradient(135deg, #1a1a2e, #16213e);
          border: 1px solid rgba(255, 255, 255, 0.2);
          border-radius: 16px;
          padding: 32px;
          text-align: center;
          max-width: 320px;
        }

        .handoff-prompt h3 {
          color: white;
          font-size: 18px;
          margin-bottom: 12px;
        }

        .handoff-prompt p {
          color: rgba(255, 255, 255, 0.7);
          font-size: 14px;
          margin-bottom: 20px;
        }

        .handoff-btn {
          background: linear-gradient(135deg, #ef4444, #dc2626);
          color: white;
          border: none;
          padding: 14px 28px;
          border-radius: 10px;
          font-size: 16px;
          font-weight: 600;
          cursor: pointer;
          display: flex;
          align-items: center;
          gap: 10px;
          margin: 0 auto;
          transition: transform 0.2s, box-shadow 0.2s;
        }

        .handoff-btn:hover {
          transform: translateY(-2px);
          box-shadow: 0 8px 20px rgba(239, 68, 68, 0.4);
        }

        .handoff-hint {
          font-size: 12px !important;
          color: rgba(255, 255, 255, 0.5) !important;
          margin-top: 16px !important;
          margin-bottom: 0 !important;
        }

        .trace-log {
          border-top: 1px solid rgba(255, 255, 255, 0.1);
          padding-top: 12px;
          margin-top: 12px;
        }

        .trace-log-header {
          font-size: 12px;
          color: rgba(255, 255, 255, 0.6);
          margin-bottom: 8px;
          display: flex;
          align-items: center;
          gap: 6px;
        }

        .trace-entry {
          font-size: 11px;
          padding: 6px 8px;
          background: rgba(255, 255, 255, 0.05);
          border-radius: 4px;
          margin-bottom: 4px;
          display: flex;
          gap: 8px;
        }

        .trace-entry.handoff {
          background: rgba(239, 68, 68, 0.2);
          border-left: 2px solid #ef4444;
        }

        .trace-entry.user_input,
        .trace-entry.user_action {
          background: rgba(59, 130, 246, 0.2);
          border-left: 2px solid #3b82f6;
        }

        .trace-entry.completion {
          background: rgba(16, 185, 129, 0.2);
          border-left: 2px solid #10b981;
        }

        .trace-type {
          color: rgba(255, 255, 255, 0.5);
          font-family: monospace;
        }

        .trace-message {
          color: rgba(255, 255, 255, 0.8);
        }

        .agent-cursor.paused {
          opacity: 0.5;
        }

        .action-item {
          cursor: pointer;
          transition: background 0.15s;
        }

        .action-item:hover {
          background: rgba(255, 255, 255, 0.1);
        }
      `}</style>
    </div>
  );
}

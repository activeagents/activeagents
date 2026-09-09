import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSync } from 'esbuild';
import { createRequire } from 'node:module';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const require = createRequire(import.meta.url);
const bundled = buildSync({
  entryPoints: ['app/javascript/components/dashboard/ExternalEvaluationReport.jsx'],
  bundle: true, platform: 'node', format: 'cjs', write: false, external: ['react'],
}).outputFiles[0].text;
const componentModule = { exports: {} };
new Function('require', 'module', 'exports', bundled)(require, componentModule, componentModule.exports);
const { ExternalEvaluationReportContent } = componentModule.exports;

function render(results) {
  const run = {
    id: 8, run_id: 'report-1', samples_passed: 1, samples_evaluated: results.length,
    report: { results, judge: 'synthetic-judge', metadata: { judge_trace_ids: ['verdict-1'] } },
  };
  return renderToStaticMarkup(React.createElement(ExternalEvaluationReportContent, {
    evaluation: { id: 4, config: { source: 'example-app' } }, colors: {}, run, runs: [run], runId: 8, setRunId: () => {},
  }));
}

test('renders grades, model totals, answers and response/judge/run trace links', () => {
  const html = render([
    { scenario_key: 'greeting', label: 'model-a', status: 'passed', score: 0.9, prompt: 'Say hello', answer: 'Hello', input_tokens: 10, output_tokens: 5, duration_ms: 100,
      metadata: { trace_id: 'response-1', judge_trace_ids: ['judge-1'] } },
    { scenario_key: 'farewell', label: 'model-a', status: 'failed', score: 0.1, fault: 'missing_content', recommendation: 'Include a farewell.', input_tokens: 20, output_tokens: 7, duration_ms: 300 },
  ]);
  for (const text of ['greeting', 'passed', 'failed', '0.50', '30 / 12', '200 ms', 'Include a farewell.', 'Hello']) assert.ok(html.includes(text), text);
  for (const id of ['response-1', 'judge-1', 'verdict-1']) assert.ok(html.includes(`/dashboard/traces?trace=${id}`));
  assert.ok(html.includes('/dashboard/evaluations?evaluation=4&amp;run=8'));
});

test('keeps unscored results distinct from zero and escapes external markup', () => {
  const html = render([{ scenario_key: 'unsafe', label: 'model-a', status: 'errored', prompt: '<img src=x onerror=alert(1)>',
    answer: '<script>alert(1)</script>', recommendation: '<a href="javascript:alert(1)">click</a>',
    metadata: { trace_id: 'javascript:alert(1)' } }]);
  assert.ok(html.includes('Unscored'));
  assert.ok(html.includes('&lt;script&gt;'));
  assert.ok(!html.includes('<script>'));
  assert.ok(!html.includes('<img'));
  assert.ok(!html.includes('href="javascript:'));
  assert.ok(html.includes('/dashboard/traces?trace=javascript%3Aalert(1)'));
});

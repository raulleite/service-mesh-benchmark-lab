import http from 'k6/http';
import { sleep } from 'k6';
import { check } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';
import { buildMeasurementDurationSeconds, buildRequestJitterMs, buildScenarios } from './scenarios.js';

const targetEndpoint = __ENV.TARGET_ENDPOINT || 'http://localhost:8080/invoke';
const topology = __ENV.TOPOLOGY || 'two-hop';
const requestJitterMs = buildRequestJitterMs();
const measurementHttpReqs = new Counter('measurement_http_reqs');
const measurementHttpReqDuration = new Trend('measurement_http_req_duration', true);
const measurementHttpReqFailed = new Rate('measurement_http_req_failed');

export const options = {
  scenarios: buildScenarios(),
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(99)<5000']
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max']
};

function buildInvocationUrl(phase) {
  const separator = targetEndpoint.includes('?') ? '&' : '?';
  return `${targetEndpoint}${separator}topology=${topology}&phase=${phase}`;
}

function executeRequest(phase) {
  if (requestJitterMs > 0) {
    sleep(Math.random() * requestJitterMs / 1000);
  }

  const response = http.get(buildInvocationUrl(phase), {
    tags: { topology, phase }
  });

  if (phase === 'measurement') {
    measurementHttpReqs.add(1);
    measurementHttpReqDuration.add(response.timings.duration);
    measurementHttpReqFailed.add(response.status !== 200);
  }

  check(response, {
    'status is 200': (r) => r.status === 200,
    'body includes topology': (r) => r.body && r.body.includes(topology)
  });
}

export function warmup() {
  executeRequest('warmup');
}

export function ignored() {
  executeRequest('ignored');
}

export function measurement() {
  executeRequest('measurement');
}

export default function () {
  executeRequest('measurement');
}

function buildSummaryMetrics(data) {
  const metrics = { ...data.metrics };
  const measurementDurationSeconds = buildMeasurementDurationSeconds();

  if (metrics.measurement_http_reqs) {
    const count = metrics.measurement_http_reqs.values.count ?? 0;

    metrics.http_reqs = {
      ...metrics.measurement_http_reqs,
      values: {
        ...metrics.measurement_http_reqs.values,
        rate: measurementDurationSeconds > 0 ? count / measurementDurationSeconds : 0
      }
    };
  }

  if (metrics.measurement_http_req_duration) {
    metrics.http_req_duration = {
      ...metrics.measurement_http_req_duration,
      thresholds: metrics.http_req_duration?.thresholds
    };
  }

  if (metrics.measurement_http_req_failed) {
    metrics.http_req_failed = {
      ...metrics.measurement_http_req_failed,
      thresholds: metrics.http_req_failed?.thresholds
    };
  }

  return metrics;
}

export function handleSummary(data) {
  const output = {
    topology,
    targetEndpoint,
    generatedAt: new Date().toISOString(),
    metrics: buildSummaryMetrics(data)
  };

  return {
    stdout: JSON.stringify(output, null, 2),
    [__ENV.K6_SUMMARY_EXPORT || 'results/runs/k6-summary.json']: JSON.stringify(output, null, 2)
  };
}
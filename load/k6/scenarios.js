export const warmupStages = [
  { target: 10, duration: '30s' },
  { target: 50, duration: '30s' }
];

export const measurementStages = [
  { target: 10, duration: '60s' },
  { target: 100, duration: '60s' },
  { target: 250, duration: '60s' },
  { target: 500, duration: '60s' },
  { target: 750, duration: '60s' },
  { target: 1000, duration: '60s' }
];

export const quickValidationStages = [
  { target: 10, duration: '10s' },
  { target: 100, duration: '15s' },
  { target: 250, duration: '15s' }
];

export const plateau400Stages = [
  { target: 10, duration: '30s' },
  { target: 50, duration: '30s' },
  { target: 100, duration: '30s' },
  { target: 250, duration: '30s' },
  { target: 400, duration: '90s' }
];

function getPreset() {
  return (__ENV.K6_STAGE_PRESET || 'default').toLowerCase();
}

function getNumberEnv(name, fallback) {
  const raw = __ENV[name];
  if (raw === undefined || raw === '') {
    return fallback;
  }

  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function getDurationEnv(name, fallback) {
  return __ENV[name] || fallback;
}

function parseDurationToSeconds(duration) {
  const match = String(duration).trim().match(/^(\d+(?:\.\d+)?)(ms|s|m|h)$/);

  if (!match) {
    return 0;
  }

  const value = Number(match[1]);
  const unit = match[2];

  if (!Number.isFinite(value)) {
    return 0;
  }

  if (unit === 'ms') {
    return value / 1000;
  }

  if (unit === 'm') {
    return value * 60;
  }

  if (unit === 'h') {
    return value * 3600;
  }

  return value;
}

function getStagesDurationSeconds(stages) {
  return stages.reduce((total, stage) => total + parseDurationToSeconds(stage.duration), 0);
}

function getVideo1000WarmupDuration() {
  return getDurationEnv('K6_VIDEO1000_WARMUP_DURATION', '20s');
}

function getVideo1000IgnoredDuration() {
  return getDurationEnv('K6_VIDEO1000_IGNORED_DURATION', '10s');
}

function getVideo1000MeasurementStartTime() {
  const totalSeconds = parseDurationToSeconds(getVideo1000WarmupDuration()) + parseDurationToSeconds(getVideo1000IgnoredDuration());
  return `${totalSeconds}s`;
}

function buildVideo172Stages(maxVUs) {
  const firstStep = Math.max(1, Math.ceil(maxVUs * 0.25));
  const secondStep = Math.max(firstStep, Math.ceil(maxVUs * 0.5));
  const thirdStep = Math.max(secondStep, Math.ceil(maxVUs * 0.75));
  const stepDuration = getDurationEnv('K6_VIDEO172_RAMP_STEP_DURATION', '5s');

  return [
    { target: firstStep, duration: stepDuration },
    { target: secondStep, duration: stepDuration },
    { target: thirdStep, duration: stepDuration },
    { target: maxVUs, duration: stepDuration },
    { target: maxVUs, duration: getDurationEnv('K6_VIDEO172_HOLD_DURATION', '10s') },
    { target: 0, duration: getDurationEnv('K6_VIDEO172_RAMP_DOWN_DURATION', '5s') }
  ];
}

function buildVideo1000Stages() {
  const maxRps = getNumberEnv('K6_VIDEO1000_MAX_RPS', 1000);
  const stepRps = Math.max(1, getNumberEnv('K6_VIDEO1000_RAMP_STEP', 100));
  const stepDuration = getDurationEnv('K6_VIDEO1000_RAMP_STEP_DURATION', '15s');
  const stages = [];

  for (let target = stepRps; target <= maxRps; target += stepRps) {
    stages.push({ target, duration: stepDuration });
  }

  return stages;
}

export function buildScenarios() {
  const preset = getPreset();

  if (preset === 'lesson172') {
    const maxVUs = getNumberEnv('K6_LESSON172_MAX_VUS', 100);

    return {
      lesson172_like: {
        executor: 'ramping-vus',
        startVUs: getNumberEnv('K6_LESSON172_START_VUS', 1),
        stages: [
          { target: maxVUs, duration: getDurationEnv('K6_LESSON172_RAMP_DURATION', '100ms') },
          { target: maxVUs, duration: getDurationEnv('K6_LESSON172_HOLD_DURATION', '30s') },
          { target: 0, duration: getDurationEnv('K6_LESSON172_RAMP_DOWN_DURATION', '100ms') }
        ],
        gracefulRampDown: '0s'
      }
    };
  }

  if (preset === 'video172') {
    const maxVUs = getNumberEnv('K6_VIDEO172_MAX_VUS', 100);

    return {
      video172_like: {
        executor: 'ramping-vus',
        startVUs: getNumberEnv('K6_VIDEO172_START_VUS', 1),
        stages: buildVideo172Stages(maxVUs),
        gracefulRampDown: '0s'
      }
    };
  }

  if (preset === 'video1000') {
    return {
      warmup: {
        exec: 'warmup',
        executor: 'constant-arrival-rate',
        rate: getNumberEnv('K6_VIDEO1000_WARMUP_RPS', 100),
        timeUnit: '1s',
        duration: getVideo1000WarmupDuration(),
        preAllocatedVUs: getNumberEnv('K6_VIDEO1000_PRE_ALLOCATED_VUS', 400),
        maxVUs: getNumberEnv('K6_VIDEO1000_MAX_VUS', 4000)
      },
      ignored: {
        exec: 'ignored',
        executor: 'constant-arrival-rate',
        startTime: getVideo1000WarmupDuration(),
        rate: getNumberEnv('K6_VIDEO1000_WARMUP_RPS', 100),
        timeUnit: '1s',
        duration: getVideo1000IgnoredDuration(),
        preAllocatedVUs: getNumberEnv('K6_VIDEO1000_PRE_ALLOCATED_VUS', 400),
        maxVUs: getNumberEnv('K6_VIDEO1000_MAX_VUS', 4000)
      },
      measurement: {
        exec: 'measurement',
        executor: 'ramping-arrival-rate',
        startTime: getVideo1000MeasurementStartTime(),
        startRate: getNumberEnv('K6_VIDEO1000_START_RPS', 0),
        timeUnit: '1s',
        preAllocatedVUs: getNumberEnv('K6_VIDEO1000_PRE_ALLOCATED_VUS', 400),
        maxVUs: getNumberEnv('K6_VIDEO1000_MAX_VUS', 4000),
        stages: buildVideo1000Stages()
      }
    };
  }

  return {
    deterministic_rps: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: getNumberEnv('K6_PRE_ALLOCATED_VUS', 200),
      maxVUs: getNumberEnv('K6_MAX_VUS', 2000),
      stages: buildStages()
    }
  };
}

export function buildMeasurementDurationSeconds() {
  const preset = getPreset();

  if (preset === 'video1000') {
    return getStagesDurationSeconds(buildVideo1000Stages());
  }

  return 0;
}

export function buildRequestJitterMs() {
  const preset = getPreset();

  if (preset === 'lesson172' || preset === 'video172' || preset === 'video1000') {
    // In the original lesson 172 client, scaleInterval=1 means rand.Intn(1) always returns 0.
    return getNumberEnv('K6_REQUEST_JITTER_MS', 0);
  }

  return getNumberEnv('K6_REQUEST_JITTER_MS', 0);
}

export function buildStages() {
  const preset = getPreset();
  const rampDown = { target: 0, duration: '15s' };

  if (preset === 'quick') {
    return [...quickValidationStages, { target: 0, duration: '5s' }];
  }

  if (preset === 'plateau400') {
    return [...plateau400Stages, rampDown];
  }

  return [...warmupStages, ...measurementStages, rampDown];
}
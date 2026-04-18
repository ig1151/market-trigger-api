#!/bin/bash
set -e

mkdir -p src/{routes,middleware,services,types}

cat > package.json << 'EOF'
{
  "name": "market-trigger-api",
  "version": "1.0.0",
  "description": "Agent-ready market trigger API. Submit conditions and get instant trigger signals — when to act, not just what to do.",
  "main": "dist/index.js",
  "scripts": {
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "helmet": "^7.1.0",
    "joi": "^17.11.0"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.3.2"
  }
}
EOF

cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
EOF

cat > render.yaml << 'EOF'
services:
  - type: web
    name: market-trigger-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
EOF

cat > .gitignore << 'EOF'
node_modules/
dist/
.env
*.log
EOF

cat > .env << 'EOF'
PORT=3000
EOF

cat > src/types/index.ts << 'EOF'
export interface TriggerConditions {
  min_impact_score?: number;
  max_impact_score?: number;
  action_bias?: string | string[];
  sentiment?: string | string[];
  min_confidence?: number;
  event_types?: string[];
  impact_horizon?: string | string[];
  freshness?: string | string[];
  require_risk_warning?: boolean;
  forbid_risk_warning?: boolean;
}

export interface NewsImpactContext {
  asset?: string;
  sentiment?: string;
  impact_score?: number;
  impact_horizon?: string;
  action_bias?: string;
  confidence?: number;
  event_type?: string;
  consensus?: string;
  freshness?: string;
  risk_warning?: string | null;
  drivers?: string[];
  watch_items?: string[];
}

export interface MarketSignalContext {
  asset?: string;
  decision?: string;
  confidence?: number;
  risk?: string;
  verdict?: string;
  trend?: string;
  momentum?: string;
}

export interface TriggerContext {
  news_impact?: NewsImpactContext;
  market_signal?: MarketSignalContext;
}

export interface TriggerRequest {
  asset: string;
  conditions: TriggerConditions;
  context: TriggerContext;
}

export interface TriggerResponse {
  asset: string;
  trigger: boolean;
  urgency: 'high' | 'medium' | 'low' | 'none';
  recommended_action: string;
  reason: string;
  conditions_met: string[];
  conditions_failed: string[];
  score: number;
  analyzedAt: string;
}
EOF

cat > src/middleware/logger.ts << 'EOF'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
EOF

cat > src/middleware/requestLogger.ts << 'EOF'
import { Request, Response, NextFunction } from 'express';
import { logger } from './logger';

export function requestLogger(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();
  res.on('finish', () => {
    logger.info({ method: req.method, path: req.path, status: res.statusCode, ms: Date.now() - start });
  });
  next();
}
EOF

cat > src/middleware/rateLimiter.ts << 'EOF'
import rateLimit from 'express-rate-limit';

export const rateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Too many requests',
    message: 'Rate limit exceeded. Max 200 requests per 15 minutes.'
  }
});
EOF

cat > src/services/triggerEngine.ts << 'EOF'
import { TriggerRequest, TriggerResponse } from '../types';

function matchesArray(value: string | undefined, condition: string | string[]): boolean {
  if (!value) return false;
  if (Array.isArray(condition)) return condition.map(c => c.toLowerCase()).includes(value.toLowerCase());
  return value.toLowerCase() === condition.toLowerCase();
}

export function evaluateTrigger(input: TriggerRequest): TriggerResponse {
  const { conditions, context } = input;
  const news = context.news_impact;
  const signal = context.market_signal;

  const conditions_met: string[] = [];
  const conditions_failed: string[] = [];

  const check = (name: string, passed: boolean) => {
    if (passed) conditions_met.push(name);
    else conditions_failed.push(name);
  };

  // min_impact_score
  if (conditions.min_impact_score !== undefined) {
    check('min_impact_score', news?.impact_score !== undefined && news.impact_score >= conditions.min_impact_score);
  }

  // max_impact_score
  if (conditions.max_impact_score !== undefined) {
    check('max_impact_score', news?.impact_score !== undefined && news.impact_score <= conditions.max_impact_score);
  }

  // action_bias
  if (conditions.action_bias !== undefined) {
    check('action_bias', matchesArray(news?.action_bias, conditions.action_bias));
  }

  // sentiment
  if (conditions.sentiment !== undefined) {
    check('sentiment', matchesArray(news?.sentiment, conditions.sentiment));
  }

  // min_confidence (checks both news and market signal)
  if (conditions.min_confidence !== undefined) {
    const newsConf = news?.confidence ?? 0;
    const signalConf = signal?.confidence ?? 0;
    const bestConf = Math.max(newsConf, signalConf);
    check('min_confidence', bestConf >= conditions.min_confidence);
  }

  // event_types
  if (conditions.event_types !== undefined) {
    check('event_types', matchesArray(news?.event_type, conditions.event_types));
  }

  // impact_horizon
  if (conditions.impact_horizon !== undefined) {
    check('impact_horizon', matchesArray(news?.impact_horizon, conditions.impact_horizon));
  }

  // freshness
  if (conditions.freshness !== undefined) {
    check('freshness', matchesArray(news?.freshness, conditions.freshness));
  }

  // require_risk_warning
  if (conditions.require_risk_warning === true) {
    check('require_risk_warning', !!news?.risk_warning);
  }

  // forbid_risk_warning
  if (conditions.forbid_risk_warning === true) {
    check('forbid_risk_warning', !news?.risk_warning);
  }

  // market signal decision
  if (signal?.decision !== undefined && conditions.action_bias !== undefined) {
    const decisionMap: Record<string, string> = {
      strong_buy: 'buy', buy: 'buy',
      strong_sell: 'sell', sell: 'sell',
      neutral: 'hold'
    };
    const mappedDecision = decisionMap[signal.decision] || signal.decision;
    check('market_signal_aligned', matchesArray(mappedDecision, conditions.action_bias));
  }

  const total = conditions_met.length + conditions_failed.length;
  const score = total > 0 ? Math.round((conditions_met.length / total) * 100) : 0;
  const trigger = conditions_failed.length === 0 && conditions_met.length > 0;

  const urgency = !trigger ? 'none' :
    score === 100 && (news?.impact_score ?? 0) >= 80 ? 'high' :
    score >= 75 ? 'medium' : 'low';

  const recommended_action = !trigger ? 'wait' :
    conditions.action_bias === 'buy' || conditions.action_bias?.includes?.('buy') ? 'enter_position' :
    conditions.action_bias === 'sell' || conditions.action_bias?.includes?.('sell') ? 'exit_position' :
    'monitor_closely';

  const reason = trigger
    ? `All ${conditions_met.length} condition(s) met — ${urgency} urgency signal detected`
    : `${conditions_failed.length} condition(s) not met: ${conditions_failed.join(', ')}`;

  return {
    asset: input.asset.toUpperCase(),
    trigger,
    urgency,
    recommended_action,
    reason,
    conditions_met,
    conditions_failed,
    score,
    analyzedAt: new Date().toISOString()
  };
}
EOF

cat > src/routes/health.ts << 'EOF'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'market-trigger-api',
    version: '1.0.0',
    uptime: Math.floor(process.uptime()),
    timestamp: new Date().toISOString()
  });
});

export default router;
EOF

cat > src/routes/trigger.ts << 'EOF'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { evaluateTrigger } from '../services/triggerEngine';
import { logger } from '../middleware/logger';

const router = Router();

const schema = Joi.object({
  asset: Joi.string().min(1).max(20).uppercase().required(),
  conditions: Joi.object({
    min_impact_score: Joi.number().min(0).max(100).optional(),
    max_impact_score: Joi.number().min(0).max(100).optional(),
    action_bias: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    sentiment: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    min_confidence: Joi.number().min(0).max(1).optional(),
    event_types: Joi.array().items(Joi.string()).optional(),
    impact_horizon: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    freshness: Joi.alternatives().try(
      Joi.string(),
      Joi.array().items(Joi.string())
    ).optional(),
    require_risk_warning: Joi.boolean().optional(),
    forbid_risk_warning: Joi.boolean().optional()
  }).min(1).required(),
  context: Joi.object({
    news_impact: Joi.object().optional(),
    market_signal: Joi.object().optional()
  }).min(1).required()
});

router.post('/', async (req: Request, res: Response): Promise<void> => {
  const { error, value } = schema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Invalid request', message: error.details[0].message });
    return;
  }

  try {
    const result = evaluateTrigger(value);
    res.json(result);
  } catch (err: any) {
    const msg: string = err.message || 'Unknown error';
    logger.error({ asset: value.asset, msg }, 'Trigger error');
    res.status(500).json({ error: 'Internal server error', message: msg });
  }
});

export default router;
EOF

cat > src/routes/docs.ts << 'EOF'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    service: 'Market Trigger API',
    version: '1.0.0',
    description: 'Agent-ready trigger API. Submit conditions and context from your market signals — get instant trigger decisions with urgency and recommended action.',
    endpoints: [
      { method: 'POST', path: '/v1/trigger', description: 'Evaluate trigger conditions against market signal and news impact context' },
      { method: 'GET', path: '/v1/health', description: 'Health check' },
      { method: 'GET', path: '/docs', description: 'Documentation' },
      { method: 'GET', path: '/openapi.json', description: 'OpenAPI spec' }
    ],
    conditions: {
      min_impact_score: 'Minimum news impact score (0-100)',
      max_impact_score: 'Maximum news impact score (0-100)',
      action_bias: 'Required action bias: buy | sell | hold | watch',
      sentiment: 'Required sentiment: bullish | bearish | neutral',
      min_confidence: 'Minimum confidence score (0-1)',
      event_types: 'Allowed event types: regulation | listing | exploit | institutional | other',
      impact_horizon: 'Required horizon: 1h | 24h | 7d',
      freshness: 'Required freshness: breaking | recent | stale',
      forbid_risk_warning: 'Trigger only if no risk warning present',
      require_risk_warning: 'Trigger only if risk warning is present'
    },
    urgency: {
      high: 'All conditions met + impact score above 80',
      medium: 'All conditions met + score above 75',
      low: 'All conditions met',
      none: 'Trigger not fired'
    },
    example: {
      asset: 'BTC',
      conditions: {
        min_impact_score: 80,
        action_bias: 'buy',
        sentiment: 'bullish',
        min_confidence: 0.75,
        forbid_risk_warning: true
      },
      context: {
        news_impact: {
          sentiment: 'bullish',
          impact_score: 85,
          action_bias: 'buy',
          confidence: 0.8,
          event_type: 'regulation',
          freshness: 'breaking',
          risk_warning: null
        }
      }
    }
  });
});

export default router;
EOF

cat > src/routes/openapi.ts << 'EOF'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    openapi: '3.0.0',
    info: { title: 'Market Trigger API', version: '1.0.0', description: 'Agent-ready market trigger API for automated trading decisions' },
    servers: [{ url: 'https://market-trigger-api.onrender.com' }],
    paths: {
      '/v1/trigger': {
        post: {
          summary: 'Evaluate trigger conditions against market context',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['asset', 'conditions', 'context'],
                  properties: {
                    asset: { type: 'string', example: 'BTC' },
                    conditions: { type: 'object' },
                    context: { type: 'object' }
                  }
                }
              }
            }
          },
          responses: {
            '200': { description: 'Trigger evaluation response' },
            '400': { description: 'Invalid request' },
            '500': { description: 'Server error' }
          }
        }
      },
      '/v1/health': {
        get: { summary: 'Health check', responses: { '200': { description: 'OK' } } }
      }
    }
  });
});

export default router;
EOF

cat > src/index.ts << 'EOF'
import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import { requestLogger } from './middleware/requestLogger';
import { rateLimiter } from './middleware/rateLimiter';
import triggerRouter from './routes/trigger';
import healthRouter from './routes/health';
import docsRouter from './routes/docs';
import openapiRouter from './routes/openapi';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());
app.use(requestLogger);
app.use(rateLimiter);

app.use('/v1/health', healthRouter);
app.use('/v1/trigger', triggerRouter);
app.use('/docs', docsRouter);
app.use('/openapi.json', openapiRouter);

app.get('/', (_req, res) => {
  res.json({
    service: 'Market Trigger API',
    version: '1.0.0',
    docs: '/docs',
    health: '/v1/health',
    example: 'POST /v1/trigger'
  });
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: `Market Trigger API running on port ${PORT}` }));
});

export default app;
EOF

echo "✅ All files created."
echo ""
echo "Next steps:"
echo "  1. npm install"
echo "  2. npm run dev"
echo "  3. Test: POST /v1/trigger"
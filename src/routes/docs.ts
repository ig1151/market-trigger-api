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

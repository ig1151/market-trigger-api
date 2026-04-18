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

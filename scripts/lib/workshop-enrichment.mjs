import { readFileSync } from 'node:fs';
import Ajv from 'ajv';

export const schema = JSON.parse(readFileSync(new URL('../../contracts/research/v1/workshop-enrichment.schema.json', import.meta.url)));
const validate = new Ajv({ allErrors: true, strict: true }).compile(schema);
const isWebUrl = value => { try { return ['https:', 'http:'].includes(new URL(value).protocol); } catch { return false; } };

export function assessEnrichment(data, approvalId, grounding = []) {
  const shapeValid = validate(data);
  const schemaErrors = structuredClone(validate.errors ?? []);
  const issues = [];
  if (!shapeValid) return { shapeValid, schemaErrors, issues, usableCard: false };
  if (data.approval_id !== approvalId) issues.push('approval_id_mismatch');
  const price = data.eu_control_price;
  if (price.amount_nok === null) issues.push('price_missing');
  if (price.amount_nok !== null && (!isWebUrl(price.source_url) || price.price_type === 'unknown')) issues.push('price_source_or_type_missing');
  if (data.reputation.rating === null) issues.push('rating_missing');
  if (data.reputation.review_count === null) issues.push('review_count_missing');
  if (data.reputation.rating !== null && !isWebUrl(data.reputation.source_url)) issues.push('rating_source_missing');
  return { shapeValid, schemaErrors, issues, usableCard: issues.length === 0,
    citationCount: grounding.reduce((n, g) => n + (g.citations?.length ?? 0), 0) };
}

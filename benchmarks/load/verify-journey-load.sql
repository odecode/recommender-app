-- Independent durable evidence for one generated prefix of journey accounts.
-- Prefix matching uses a literal left substring, not LIKE: underscores in the
-- generated credential prefix must not become SQL wildcards.
SELECT
  (SELECT count(*) FROM ratings r JOIN accounts a ON a.id=r.account_id
    WHERE left(a.username,length(:'username_prefix')+1)=:'username_prefix' || '-'),
  (SELECT count(*) FROM ratings r JOIN accounts a ON a.id=r.account_id
    WHERE left(a.username,length(:'username_prefix')+1)=:'username_prefix' || '-'
      AND r.item_id BETWEEN 0 AND 4 AND r.rating=5),
  (SELECT count(*) FROM rating_operation_receipts r JOIN accounts a ON a.id=r.account_id
    WHERE left(a.username,length(:'username_prefix')+1)=:'username_prefix' || '-'),
  (SELECT count(*) FROM rating_operation_receipts r JOIN accounts a ON a.id=r.account_id
    WHERE left(a.username,length(:'username_prefix')+1)=:'username_prefix' || '-'
      AND r.item_id BETWEEN 0 AND 4 AND r.rating=5 AND r.status='saved'),
  (SELECT count(DISTINCT r.operation_id) FROM rating_operation_receipts r JOIN accounts a ON a.id=r.account_id
    WHERE left(a.username,length(:'username_prefix')+1)=:'username_prefix' || '-' AND r.status='saved'),
  (SELECT count(DISTINCT a.id) FROM ratings r JOIN accounts a ON a.id=r.account_id
    WHERE left(a.username,length(:'username_prefix')+1)=:'username_prefix' || '-');

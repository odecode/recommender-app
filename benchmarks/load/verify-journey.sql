SELECT
  (SELECT count(*) FROM ratings r JOIN accounts a ON a.id=r.account_id
    WHERE a.username=:'username' AND r.item_id BETWEEN 0 AND 4 AND r.rating=5),
  (SELECT count(*) FROM rating_operation_receipts r JOIN accounts a ON a.id=r.account_id
    WHERE a.username=:'username' AND r.item_id BETWEEN 0 AND 4 AND r.rating=5 AND r.status='saved'),
  (SELECT count(DISTINCT r.operation_id) FROM rating_operation_receipts r JOIN accounts a ON a.id=r.account_id
    WHERE a.username=:'username' AND r.status='saved');

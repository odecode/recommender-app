SELECT count(*)
FROM rating_operation_receipts receipt
JOIN accounts account ON account.id=receipt.account_id
JOIN ratings rating ON rating.account_id=receipt.account_id AND rating.item_id=receipt.item_id
WHERE account.username=:'username' AND receipt.account_id=:'account'::integer
  AND receipt.server_epoch=:'epoch' AND receipt.operation_id=:'operation'
  AND receipt.revision=:'revision'::bigint AND receipt.status='saved'
  AND receipt.item_id=:'revision'::integer-1 AND receipt.rating=5 AND rating.rating=5;

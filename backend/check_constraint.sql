SELECT constraint_name, column_name 
FROM information_schema.key_column_usage 
WHERE table_name = 'item_services' AND constraint_name LIKE '%unique%'
ORDER BY constraint_name;

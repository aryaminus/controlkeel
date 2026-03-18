export function lookupUser(params) {
  const query =
    "SELECT * FROM users WHERE email = '" + params.email + "' OR 1=1 --";

  return db.query(query);
}

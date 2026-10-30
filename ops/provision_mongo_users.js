// Operator-run preparation on the existing writable primary, before enabling auth.
// Input comes from process environment; passwords are never printed or reset.
const admin = db.getSiblingDB('admin');
const application = db.getSiblingDB('autanalysis');
const rootUser = process.env.MONGO_ROOT_USERNAME;
const rootPassword = process.env.MONGO_ROOT_PASSWORD;
const appUser = process.env.MONGO_APP_USERNAME;
const appPassword = process.env.MONGO_APP_PASSWORD;
if (!rootUser || !appUser || rootUser === appUser || !rootPassword || !appPassword ||
    rootPassword.length < 32 || appPassword.length < 32) {
  throw new Error('Require distinct usernames and random passwords of at least 32 characters');
}
if (!db.hello().isWritablePrimary) throw new Error('Writable replica set primary required');
const existingRoot = admin.getUser(rootUser);
const existingApp = application.getUser(appUser);
const sameRoles = (user, role, database) => user.roles.length === 1 &&
  user.roles[0].role === role && user.roles[0].db === database;
if (existingRoot && !sameRoles(existingRoot, 'root', 'admin')) throw new Error('Existing recovery account has different roles; review manually');
if (existingApp && !sameRoles(existingApp, 'readWrite', 'autanalysis')) throw new Error('Existing app account has different roles; review manually');
if (existingRoot && !admin.auth(rootUser, rootPassword)) throw new Error('Existing recovery credentials differ; no password changed');
if (existingApp && !application.auth(appUser, appPassword)) throw new Error('Existing application credentials differ; no password changed');
if (!existingApp) application.createUser({user: appUser, pwd: appPassword, roles: [{role: 'readWrite', db: 'autanalysis'}]});
if (!existingRoot) admin.createUser({user: rootUser, pwd: rootPassword, roles: [{role: 'root', db: 'admin'}]});
print('Accounts prepared; credentials unchanged for any existing accounts. Enable the keyfile overlay separately.');

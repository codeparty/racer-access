var deepCopy = require('racer-util/object').deepCopy;

exports = module.exports = plugin;

function plugin (racer, options) {
  var Store = racer.Store;

  racer.on('store', function (store) {
    /**
     * Assign the connect session to ShareJS's useragent (there is 1 useragent per
     * browser tab or window that is connected to our server via browserchannel).
     * We'll probably soon move this into racer core, so developers won't need to
     * remember to have this code here.
     */
    store.shareClient.use('connect', function (shareRequest, next) {
      var req = shareRequest.req;
      if (req && req.session) shareRequest.agent.connectSession = req.session;
      next();
    });
  });

  /**
   * A convenience method for declaring access control on queries. For usage, see
   * the example code below (`store.onQuery('items', ...`)). This may be moved
   * into racer core. We'll want to experiment to see if this particular
   * interface is sufficient, before committing this convenience method to core.
   */
  Store.prototype.onQuery = function (collectionName, callback) {
    this.shareClient.use('query', function (shareRequest, next) {
      if (collectionName !== shareRequest.collection) return next();
      var session = shareRequest.agent.connectSession;
      shareRequest.query = deepCopy(shareRequest.query);
      callback(shareRequest.query, session, next);
    });
  };

  /**
   * A convenience method for declaring access control on writes, based on the
   * value of the document before the operation is applied to it.
   * @param {String} collectionName
   * @param {Function} callback(docId, opData, doc, connectSession, next)
   *   where next(docId, opData, docBeforeOp, session, next)
   */
  Store.prototype.preChange = createWriteHelper('pre validate', 'oldSnapshot');

  /**
   * A convenience method for declaring access control on writes, based on the
   * hypothetical result of the operation. For usage, see the example code below
   * (`store.onChange('users', ...`)). This may be moved into racer core. We'll
   * want to experiment to see if this particular interface is sufficient, before
   * committing this convenience method to core.
   * @param {String} collectionName
   * @param {Function} callback(docId, opData, doc, connectSession, callback)
   */
  Store.prototype.onChange = createWriteHelper('validate', 'snapshot');


  /**
   * A convenience method for declaring access control on reading individual
   * documents. This may be moved into racer core. We'll want to experiment to
   * see if this particular interface is sufficient, before committing this
   * convenience method to core.
   * @param {String} collectionName
   * @param {Function} callback(docId, doc, connectSession)
   */
  Store.prototype.filterDoc = function (collection, callback) {
    this.shareClient.filter( function (collectionName, docId, snapshot) {
      if (collectionName !== collection) return;
      var useragent = this;
      var doc = snapshot.data;
      return callback(docId, doc, useragent.connectSession);
    });
  };
}

/**
 * Express middleware for exposing the user to the model (accessible by the
 * server and browser only to the user, via model.get('_session.user').
 */
exports.rememberUser = function (req, res, next) {
  var model = req.getModel();
  var userId = req.session.userId;
  if (! userId) return next();
  var $me = model.at('users.' + userId);
  $me.fetch( function (err) {
    model.ref('_session.user', $me.path());
    next();
  });
};

/**
 * @param {String} shareEvent
 * @param {String} snapshotKey
 * @return {Function}
 */
function createWriteHelper (shareEvent, snapshotKey) {
  /*
   * @param {String} collectionName
   * @param {Function} callback(docId, opData, doc, connectSession, callback)
   */
  return function (collectionName, callback) {
    // `this` is store
    this.shareClient.use(shareEvent, function (shareRequest, next) {
      var collection = shareRequest.collection;
      if (collection !== collectionName) return next();
      var agent = shareRequest.agent;
      var action = shareRequest.action
      var docName = shareRequest.docName;
      var backend = shareRequest.backend;
      // opData represents the ShareJS operation
      var opData = shareRequest.opData;
      // snapshot is the snapshot of the data before or after the opData has
      // been applied (depends on snapshotKey, which correlates with shareEvent)
      var snapshot = shareRequest[snapshotKey];
      console.log(shareRequest, snapshotKey);

      var snapshotData = (opData.del) ?
        opData.prev.data :
        snapshot.data;

      opData.origin = (shareRequest.agent.stream.isServer) ?
          'server' :
          'browser';
      callback(docName, opData, snapshotData, agent.connectSession, function (err) {
        delete opData.origin;
        next(err);
      });
    });
  };
}

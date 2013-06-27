var deepCopy = require('racer-util/object').deepCopy;
var helpers = require('./helper');
var opToRacerSemantics = helpers.opToRacerSemantics;
var stringInsertToRacerChange = helpers.stringInsertToRacerChange;
var stringRemoveToRacerChange = helpers.stringRemoveToRacerChange;
var lookupSegments = helpers.lookupSegments;
var patternToRegExp = helpers.patternToRegExp

// These are events that cause a "change" event to fire
var CHANGE_EVENTS = {
  change: 1
, stringInsert: 1
, stringRemove: 1
, increment: 1
};

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

  Store.prototype.allow = function (type, pattern, callback) {
    this['_allow_' + type](pattern, callback);
  };

  Store.prototype._allow_query = function (collectionName, callback) {
    this.shareClient.use('query', function (shareRequest, next) {
      if (collectionName !== shareRequest.collection) return next();
      var session = shareRequest.agent.connectSession;
      shareRequest.query = deepCopy(shareRequest.query);
      callback(shareRequest.query, session, next);
    });
  };


  Store.prototype._allow_doc = function (collectionName, callback) {
    this.shareClient.filter( function (collection, docId, snapshot, next) {
      if (collectionName !== collection) return next();
      var useragent = this;
      var doc = snapshot.data;
      return callback(docId, doc, useragent.connectSession, next);
    });
  };

  Store.prototype._allow_change = function (pattern, callback) {
    /**
     * @param {Object} shareRequest
     * @param {String} shareRequest.action
     * @param {String} shareRequest.docName
     * @param {LiveDb} shareRequest.backend
     * @param {Object} shareRequest.opData
     * @param {Function} next(err)
     */
    this.shareClient.use('submit', function (shareRequest, next) {
      var collection = shareRequest.collection;
      if (collection !== pattern.slice(0, collection.length)) {
        return next();
      }

      // opData represents the ShareJS operation
      var opData = shareRequest.opData;

      if (opData.create) {
        var type = 'change';
        var changeTo = opData.create.data;
        // TODO Weird that changeTo is undefined (because of _createImplied)
        if (! changeTo) return next();
      } else {
        var op = opData.op;
        var parsed = opToRacerSemantics(op);
        var type = parsed[0];

        if (! CHANGE_EVENTS[type]) return callback();

        var relativeSegments = parsed[1];
        var args = parsed[2];

        // Check for patterns "collection**" or e.g., "collection.*.x.y.z**"
        if (pattern.slice(pattern.length-2, pattern.length) === '**') {
        } else {
          // Handle e.g., pattern = "collection.*.x.y.z"
          var patternSegments = pattern.split('.');
          if (patternSegments[1] !== '*') {
            console.warn('Unexpected pattern', pattern);
          }
          var patternRelativeSegments = patternSegments.slice(2);

          // Pass to next middleware if pattern does not match the mutated path
          if (relativeSegments.length !== patternRelativeSegments.length) {
            return next();
          }
          if (relativeSegments.join('.') !== patternRelativeSegments.join('.')) {
            return next();
          }

        }

        // snapshot is the snapshot of the data before or after the opData has
        var snapshotData = shareRequest.oldSnapshot.data;
        if (type === 'change') {
          var changeTo = lookupSegments(relativeSegments, snapshotData);
          var apply = null;
        } else if (type === 'stringInsert') {
          var index = args[0];
          var text = args[1];
          var changeParams = stringInsertToRacerChange(relativeSegments, index, text, snapshotData);
          var value = changeParams[0];
          var previous = changeParams[1];
        } else if (type === 'stringRemove') {
          var index = args[0];
          var text = args[1];
          var changeParams = stringRemoveToRacerChange(relativeSegments, index, text, model);
        } else if (type === 'increment') {
        }
      }

      var agent = shareRequest.agent;
      opData.origin = (shareRequest.agent.stream.isServer) ?
        'server' :
        'browser';

      // Otherwise, this access control handler is applicable
      var docName = shareRequest.docName;
      var session = shareRequest.agent.connectSession;
      callback(docName, changeTo, snapshotData, apply, session, function (err) {
        delete opData.origin;
        next(err);
      });
//      var regExp = patternToRegExp(pattern);

    });
  };

  Store.prototype._allow_create = function (pattern, callback) {
    this.shareClient.use('submit', function (shareRequest, next) {
      var collection = shareRequest.collection;
      if (collection !== pattern.slice(0, collection.length)) {
        return next();
      }

      var opData = shareRequest.opData;
      if (! opData.create) return next();
      var docName = shareRequest.docName;
      var newDoc = opData.create.data;
      var session = shareRequest.agent.connectSession;
      callback(docName, newDoc, session, next);
    });
  };

  Store.prototype._allow_remove = function (pattern, callback) {
    this.shareClient.use('submit', function (shareRequest, next) {
      var collection = shareRequest.collection; if (collection !== pattern.slice(0, collection.length)) {
        return next();
      }

      var opData = shareRequest.opData;
      if (opData.create) return next();

      var op = opData.op;
      var parsed = opToRacerSemantics(op);
      var type = parsed[0];

      if (type !== 'remove') return next();

      var relativeSegments = parsed[1];
      var args = parsed[2];

      // Check for patterns "collection**" or e.g., "collection.*.x.y.z**"
      if (pattern.slice(pattern.length-2, pattern.length) === '**') {
      } else {
        // Handle e.g., pattern = "collection.*.x.y.z"
        var patternSegments = pattern.split('.');
        if (patternSegments[1] !== '*') {
          console.warn('Unexpected pattern', pattern);
        }
        var patternRelativeSegments = patternSegments.slice(2);

        // Pass to next middleware if pattern does not match the mutated path
        if (relativeSegments.length !== patternRelativeSegments.length) {
          return next();
        }
        if (relativeSegments.join('.') !== patternRelativeSegments.join('.')) {
          return next();
        }

      }

      var docBeforeRemove = shareRequest.oldSnapshot.data;
      var index = args[0];
      var howMany = args[1];

      var docName = shareRequest.docName;
      var apply = null;
      var session = shareRequest.agent.connectSession;
      callback(docName, index, howMany, docBeforeRemove, apply, session, next);

    });
  };

  Store.prototype._allow_insert = function (pattern, callback) {
    this.shareClient.use('submit', function (shareRequest, next) {
      var relevant = isRelevantNonChange('insert', pattern, shareRequest);
      if (! relevant) return next();

      var parsed = relevant;

      var relativeSegments = parsed[1];
      var args = parsed[2];

      // Check for patterns "collection**" or e.g., "collection.*.x.y.z**"
      if (pattern.slice(pattern.length-2, pattern.length) === '**') {
      } else {
        // Handle e.g., pattern = "collection.*.x.y.z"
        var patternSegments = pattern.split('.');
        if (patternSegments[1] !== '*') {
          console.warn('Unexpected pattern', pattern);
        }
        var patternRelativeSegments = patternSegments.slice(2);

        // Pass to next middleware if pattern does not match the mutated path
        if (relativeSegments.length !== patternRelativeSegments.length) {
          return next();
        }
        if (relativeSegments.join('.') !== patternRelativeSegments.join('.')) {
          return next();
        }

      var docBeforeInsert = shareRequest.oldSnapshot.data;
      var index = args[0];
      var toInsert = args[1];

      var docName = shareRequest.docName;
      var apply = null;
      var session = shareRequest.agent.connectSession;
      callback(docName, index, toInsert, docBeforeInsert, apply, session, next);

      }
    });
  };

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
    this.shareClient.filter( function (collectionName, docId, snapshot, next) {
      if (collectionName !== collection) return next();
      var useragent = this;
      var doc = snapshot.data;
      return callback(docId, doc, useragent.connectSession, next);
    });
  };

//  Store.prototype.allow = function (type, pattern, callback) {
//    this['allow_' + type](pattern, callback);
//  };

  Store.prototype.allow_query = function (collection, callback) {
    this.shareClient.use('query', function (shareRequest, next) {
      if (collection === shareRequest.collection) return next();
      var session = shareRequest.agent.connectSession;
      shareRequest.query = deepCopy(shareRequest.query);
      callback(shareRequest.query, session, next);
    });
  };

  Store.prototype.allow_doc = function (collection, callback) {
    this.shareClient.filter( function (collectionName, docName, snapshot, next) {
      if (collectionName !== collection) return next();
      var useragent = this;
      var doc = Object.create(snapshot.data, {
        id: {value: docName}
      });
      return callback(doc, useragent.connectSession, next);
    });
  };

  Store.prototype.allow_create = function (collection, callback) {
  };

  Store.prototype.allow_destroy = function (collection, callback) {
  };

  Store.prototype.allow_all = function (pattern, callback) {
  };

  Store.prototype.allow_change = function (pattern, callback) {
  };

  Store.prototype.allow_insert = function (pattern, callback) {
  };

  Store.prototype.allow_remove = function (pattern, callback) {
  };

  Store.prototype.allow_move = function (pattern, callback) {
  };

  Store.prototype.allow_stringInsert = function (pattern, callback) {
  };

  Store.prototype.allow_stringRemove = function (pattern, callback) {
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

function isRelevantNonChange (event, pattern, shareRequest) {
  var collection = shareRequest.collection; if (collection !== pattern.slice(0, collection.length)) {
    return false;
  }

  var opData = shareRequest.opData;
  if (opData.create) return false;

  var op = opData.op;
  var parsed = opToRacerSemantics(op);
  var type = parsed[0];

  if (type !== event) return false;

  return parsed;
}

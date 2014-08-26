var deepCopy = require('racer-util/object').deepCopy;

exports = module.exports = plugin;

function plugin (racer, options) {
  var Store = racer.Store;

  function setupPreValidate (shareClient) {
    shareClient._validatorsCreate = [];
    shareClient._validatorsDel = [];
    shareClient._validatorsUpdate = [];
    shareClient.use('submit', function (shareRequest, next) {
      var useragent = this;
      var opData = shareRequest.opData;
      opData.collection = shareRequest.collection;
      opData.docName = shareRequest.docName;
      opData.connectSession = shareRequest.agent.connectSession;
      opData.origin = (shareRequest.agent.stream.isServer) ?
        'server' :
        'browser';
      next();
    });

    /**
     * @param {Object} opData
     * @param {Array} opData.op
     * @param {Number} opData.v
     * @param {String} opData.src
     * @param {Number} opData.seq
     * @param {Object} data is the current snapshot
     * @return {Error|undefined}
     */
    shareClient.preValidate = function (opData, data) {
      var collection = opData.collection;
      var docName = opData.docName;
      var connectSession = opData.connectSession;
      var origin = opData.origin;

      var validators;
      if (opData.create) {
        validators = shareClient._validatorsCreate;
      } else if (opData.del) {
        validators = shareClient._validatorsDel;
      } else {
        validators = shareClient._validatorsUpdate;
      }
      var err;
      for (var i = 0, l = validators.length; i < l; i++) {
        err = validators[i](collection, docName, opData, data.data, connectSession);
        if (err) break;
      }
      if (err) return err;
    }
  }

  racer.on('store', setupStore);
  function setupStore (store) {
    if (store._didInitAccessControl) return;
    /**
     * Assign the connect session to ShareJS's useragent (there is 1 useragent per
     * browser tab or window that is connected to our server via browserchannel).
     * We'll probably soon move this into racer core, so developers won't need to
     * remember to have this code here.
     */
    store._didInitAccessControl = true;
    store.shareClient.use('connect', function (shareRequest, next) {
      var req = shareRequest.req;
      if (req && req.session) shareRequest.agent.connectSession = req.session;
      next();
    });

    setupPreValidate(store.shareClient);
  }

  Store.prototype.allow = function (type, pattern, callback) {
    setupStore(this);
    this['_allow_' + type](pattern, callback);
  };

  /**
   * A convenience method for declaring access control on queries. This may be
   * moved into racer core. We'll want to experiment to see if this particular
   * interface is sufficient, before committing this convenience method to
   * core.
   */
  Store.prototype._allow_query = function (collectionName, callback) {
    this.shareClient.use('query', function (shareRequest, next) {
      if ((collectionName !== '**') && (collectionName !== shareRequest.collection)) {
        return next();
      }
      var session = shareRequest.agent.connectSession;
      shareRequest.query = deepCopy(shareRequest.query);
      var origin = (shareRequest.agent.stream.isServer) ?
        'server' :
        'browser';
      if (collectionName === '**') {
        callback(shareRequest.collection, shareRequest.query, session, origin, next);
      } else {
        callback(shareRequest.query, session, origin, next);
      }
    });
  };


  /**
   * A convenience method for declaring access control on reading individual
   * documents. This may be moved into racer core. We'll want to experiment to
   * see if this particular interface is sufficient, before committing this
   * convenience method to core.
   * @param {String} collectionName
   * @param {Function} callback(docId, doc, connectSession)
   */
  Store.prototype._allow_doc = function (collectionName, callback) {
    this.shareClient.filter( function (collection, docId, snapshot, next) {
      if (! docId) docId = snapshot.docName;
      if ((collectionName !== '**') && (collectionName !== collection)) {
        return next();
      }

      var useragent = this;
      var doc = snapshot.data;
      var origin = (useragent.stream.isServer) ?
        'server' :
        'browser';
      if (collectionName === '**') {
        return callback(collection, docId, doc, useragent.connectSession, origin, next);
      } else {
        return callback(docId, doc, useragent.connectSession, origin, next);
      }
    });
  };

  Store.prototype._allow_change = function (pattern, validate) {
    this.shareClient._validatorsUpdate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        var racerMethod = opToRacerMethod(opData.op);
        if (-1 === ['change', 'stringRemove', 'stringInsert', 'increment'].indexOf(racerMethod)) {
          return;
        }

        var relativeSegments = segmentsFor(racerMethod, opData);
        var isRelevantPath = relevantPath(pattern, relativeSegments);
        if (! isRelevantPath) return;

        var changeTo = calcChangeTo(racerMethod, opData, relativeSegments, snapshotData);
        if (isRelevantPath.length > 1) {
          var matches = isRelevantPath;
          return validate.apply(null, [docName].concat(matches.slice(1)).concat(changeTo, snapshotData, connectSession));
        } else {
          return validate(docName, changeTo, snapshotData, connectSession);
        }
      }
    );

    var indexOfDot = pattern.indexOf('.');
    if ((indexOfDot !== -1) && (indexOfDot + 2 === pattern.length) && pattern.charAt(pattern.length-1) === '*') {
      this.shareClient._validatorsCreate.push(
        function (collection, docName, opData, snapshotData, connectSession) {
          if (! collectionMatchesPattern(collection, pattern)) return;

          if (collection !== opData.collection) return;

          var newDoc = opData.create.data;
          return validate(docName, newDoc, connectSession);
        }
      );
    }
  };

  /**
   * A convenience method for declaring access control on creates, based on the
   * value of the document before the operation is applied to it.
   * @param {String} collectionName
   * @param {Function} callback(docId, opData, doc, connectSession, next)
   *   where next(docId, opData, docBeforeOp, session, next)
   */
  Store.prototype._allow_create = function (pattern, validate) {
    this.shareClient._validatorsCreate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        var newDoc = opData.create.data;
        return validate(docName, newDoc, connectSession);
      }
    );
  };

  /**
   * A convenience method for declaring access control on document and
   * attribute deletes, based on the value of the document before the operation
   * is applied to it.
   * @param {String} collectionName
   * @param {Function} callback(docId, opData, doc, connectSession, next)
   *   where next(docId, opData, docBeforeOp, session, next)
   */
  Store.prototype._allow_del = function (pattern, validate) {
    // If the pattern is just the collection name, then access control is being
    // set up for document deletion.
    if (pattern.indexOf('.') === -1 && pattern.indexOf('*') === -1) {
      this.shareClient._validatorsDel.push(
        function (collection, docName, opData, snapshotData, connectSession) {
          if (! collectionMatchesPattern(collection, pattern)) return;
          var docToRemove = snapshotData;
          return validate(docName, docToRemove, connectSession);
        }
      );
    } else {
      this.shareClient._validatorsUpdate.push(
        function (collection, docName, opData, snapshotData, connectSession) {
          if (! collectionMatchesPattern(collection, pattern)) return;

          var item = opData.op[0];

          // Ignore replaces (i.e., op.oi and op.od are both present);
          if (item.oi) return;

          var valueToDelete = item.od;
          if (valueToDelete === void 0) return;

          return validate(docName, valueToDelete, snapshotData, connectSession);
        }
      );
    }
  };

  Store.prototype._allow_remove = function (pattern, validate) {
    this.shareClient._validatorsUpdate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        var racerMethod = opToRacerMethod(opData.op);
        if (racerMethod !== 'remove') return;

        var relativeSegments = segmentsFor(racerMethod, opData);
        var isRelevantPath = relevantPath(pattern, relativeSegments);
        if (! isRelevantPath) return;

        var changeTo = calcChangeTo(racerMethod, opData, relativeSegments, snapshotData);
        var segments = opData.op[0].p;
        var index = segments[segments.length-1];
        var howMany = 1;
        return validate(docName, index, howMany, snapshotData, connectSession);

      }
    );
  };

  Store.prototype._allow_insert = function (pattern, validate) {
    this.shareClient._validatorsUpdate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        var racerMethod = opToRacerMethod(opData.op);
        if (racerMethod !== 'insert') return;

        var relativeSegments = segmentsFor(racerMethod, opData);
        var isRelevantPath = relevantPath(pattern, relativeSegments);
        if (! isRelevantPath) return;

        var segments = opData.op[0].p;
        var index = segments[segments.length-1];
        var toInsert = [opData.op[0].li];
        return validate(docName, index, toInsert, snapshotData, connectSession);
      }
    );
  };

  Store.prototype._allow_move = function (pattern, validate) {
    this.shareClient._validatorsUpdate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        var racerMethod = opToRacerMethod(opData.op);
        if (racerMethod !== 'move') return;

        var relativeSegments = segmentsFor(racerMethod, opData);
        var isRelevantPath = relevantPath(pattern, relativeSegments);
        if (! isRelevantPath) return;

        var segments = opData.op[0].p;
        var from = segments[segments.length-1];
        var to = opData.op[0].lm - 1;
        var howMany = 1;
        return validate(docName, from, to, howMany, snapshotData, connectSession);
      }
    );
  };

  Store.prototype._allow_all = function (pattern, validate) {
    this.shareClient._validatorsUpdate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        if (pattern === '**') {
          var racerMethod = opToRacerMethod(opData.op);
          var relativeSegments = segmentsFor(racerMethod, opData);
          return validate(docName, relativeSegments.join('.'), opData, snapshotData, connectSession);
        } else if (pattern === collection + '**') {
          var racerMethod = opToRacerMethod(opData.op);
          var relativeSegments = segmentsFor(racerMethod, opData);
          return validate(docName, relativeSegments.join('.'), opData, snapshotData, connectSession);
        } else {
          var racerMethod = opToRacerMethod(opData.op);
          var relativeSegments = segmentsFor(racerMethod, opData);
          var isRelevantPath = relevantPath(pattern, relativeSegments);
          if (! isRelevantPath) return;
          return validate(docName, relativeSegments.join('.'), opData, snapshotData, connectSession);
        }
      }
    );

    this.shareClient._validatorsCreate.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        if ((pattern === '**') || (pattern === collection + '**')) {
          var relPath = '';
          return validate(docName, relPath, opData, snapshotData, connectSession);
        }
      }
    );

    this.shareClient._validatorsDel.push(
      function (collection, docName, opData, snapshotData, connectSession) {
        if (! collectionMatchesPattern(collection, pattern)) return;
        if ((pattern === '**') || (pattern === collection + '**')) {
          if (opData.op) {
            var racerMethod = opToRacerMethod(opData.op);
            var relativeSegments = segmentsFor(racerMethod, opData);
            var relPath = relativeSegments.join('.');
            return validate(docName, relPath, opData, snapshotData, connectSession);
          } else { // else deleting entire document
            var relPath = '';
            return validate(docName, relPath, opData, snapshotData, connectSession);
          }
        } else if (! opData.del) {
          var racerMethod = opToRacerMethod(opData.op);
          var relativeSegments = segmentsFor(racerMethod, opData);
          var isRelevantPath = relevantPath(pattern, relativeSegments);
          if (! isRelevantPath) return;
          if (isRelevantPath.length > 1) {
            return validate.apply(null, [docName].concat(isRelevantPath.slice(1)).concat(relativeSegments.join('.'), opData, snapshotData, connectSession));
          } else {
            return validate(docName, relativeSegments.join('.'), opData, snapshotData, connectSession);
          }
        }
      }
    );
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

function collectionMatchesPattern (collection, pattern) {
  if (pattern === '**') return true;
  return collection === pattern.slice(0, collection.length);
}

function opToRacerMethod (op) {
  var item = op[0];

  // object replace, object insert, or object delete
  if ((item.oi !== void 0) || (item.od !== void 0)) {
    return 'change';

  // list replace
  } else if (item.li !== undefined && item.ld !== undefined) {
    return 'change';

  // List insert
  } else if (item.li !== undefined) {
    return 'insert';

  // List remove
  } else if (item.ld !== undefined) {
    return 'remove';

  // List move
  } else if (item.lm !== undefined) {
    return 'move';

  // String insert
  } else if (item.si !== undefined) {
    return 'stringInsert';

  // String remove
  } else if (item.sd !== undefined) {
    return 'stringRemove';

  // Increment
  } else if (item.na !== undefined) {
    return 'increment';
  }
}

function segmentsFor (racerEvent, opData) {
  var item = opData.op[0];
  // segments relative to doc root
  var relativeSegments = item.p;

  switch (racerEvent) {
    case 'change':
    case 'increment':
      return relativeSegments;
    case 'insert':
    case 'remove':
    case 'move':
    case 'stringInsert':
    case 'stringRemove':
      return relativeSegments.slice(0, -1);
  }
}

function relevantPath (pattern, relativeSegments) {
  if (pattern === '**') return [null].concat(relativeSegments);
  // Check for patterns "collection**" or e.g., "collection.*.x.y.z**"
  if (pattern.slice(pattern.length-2, pattern.length) === '**') {
    return true;
  } else {
    // Handle e.g., pattern = "collection.*.x.y.z"
    var patternSegments = pattern.split('.');
    if (patternSegments[1] !== '*') {
      console.warn('Unexpected pattern', pattern);
    }
    var patternRelativeSegments = patternSegments.slice(2);

    // Pass to next middleware if pattern does not match the mutated path
    if (relativeSegments.length !== patternRelativeSegments.length) {
      return false;
    }

    if (-1 === patternRelativeSegments.indexOf('*')) {
      return relativeSegments.join('.') === patternRelativeSegments.join('.');
    }
    var regExp = patternToRegExp(patternRelativeSegments.join('.'));
    var matches = regExp.exec(relativeSegments.join('.'));
    if (matches) {
      for (var i = 1, l = matches.length; i < l; i++) {
        if (/^\d+$/.test(matches[i])) {
          matches[i] = parseInt(matches[i], 10);
        }
      }
    }
    return matches;
  }
}

function calcChangeTo (racerMethod, opData, relativeSegments, snapshotData) {
  var item = opData.op[0];
  if (racerMethod === 'change') {
    return item.oi || // object replace, insert, or delete
      item.li; // list replace
  } else if (racerMethod === 'stringInsert') {
    var index = relativeSegments[relativeSegments.length-1];
    var text = item.si;
    var currText = lookupSegments(relativeSegments, snapshotData);
    return currText.slice(0, index) +
      text +
      currText.slice(index);
  } else if (racerMethod === 'stringRemove') {
    var index = relativeSegments[relativeSegments.length-1];
    var text = item.sd;
    var currText = lookupSegments(relativeSegments, snapshotData);
    return currText.slice(0, index) + currText.slice(index + text.length);
  } else if (racerMethod === 'increment') {
    var incrBy = item.na;
    return lookupSegments(relativeSegments, snapshotData) + incrBy;
  }
}

function patternToRegExp (pattern) {
  var regExpString = pattern
    .replace(/\./g, "\\.")
    .replace(/\*/g, "([^.]+)");
  return new RegExp(regExpString);
}

function lookupSegments (segments, object) {
  var curr = object;
  for (var i = 0, l = segments.length; i < l; i++) {
    var segment = segments[i];
    if (/^\d+$/.test(segment)) {
      segment = parseInt(segment, 10);
    }
    curr = curr[segment];
  }
  return curr;
}

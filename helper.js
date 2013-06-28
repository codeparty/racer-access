module.exports = {
  opToRacerSemantics: opToRacerSemantics
, stringInsertToRacerChange: stringInsertToRacerChange
, stringRemoveToRacerChange: stringRemoveToRacerChange
, lookupSegments: lookupSegments
, patternToRegExp: patternToRegExp
};


function opToRacerSemantics (op) {
  var item = op[0];

  // segments relative to doc root
  var relativeSegments= item.p;

  // object replace, object insert, or object delete
  if (item.oi || item.od) {
    var value = item.oi;
    var previous = item.od;
    return ['change', relativeSegments, [value, previous]];

  // list replace
  } else if (item.li && item.ld) {
    var value = item.li;
    var previous = item.ld;
    return ['change', relativeSegments, [value, previous]];

  // List insert
  } else if (item.li) {
    var index = relativeSegments[relativeSegments.length-1];
    var values = [item.li];
    var segmentsToList = relativeSegments.slice(0, -1)
    return ['insert', segmentsToList, [index, values]];

  // List remove
  } else if (item.ld) {
    var index = relativeSegments[relativeSegments.length-1];
    var removed = [item.ld];
    var segmentsToList = relativeSegments.slice(0, -1);
    return ['remove', segmentsToList, [index, removed.length]];

  // List move
  } else if (item.lm !== void 0) {
    var from = relativeSegments[relativeSegments.length-1];
    var to = item.lm;
    var howMany = 1;
    var segmentsToList = relativeSegments.slice(0, -1);
    return ['move', segmentsToList, [from, to, howMany]];

  // String insert
  } else if (item.si) {
    var index = relativeSegments[relativeSegments.length-1];
    var text = item.si;
    var segmentsToString = relativeSegments.slice(0, -1);
    return ['stringInsert', segmentsToString, [index, text]];

  // String remove
  } else if (item.sd) {
    var index = relativeSegments[relativeSegments.length-1];
    var text = item.sd;
    var howMany = text.length;
    var segmentsToString = relativeSegments.slice(0, -1);
    return ['stringRemove', segmentsToString, [index, howMany]];

  // Increment
  } else if (item.na !== void 0) {
    var args = [item.na];
    args.type = 'increment';
    return ['increment', relativeSegments, args];
  }
}

function stringInsertToRacerChange (segments, index, text, snapshot) {
  var value = lookupSegments(segments, snapshot);
  var previous = value.slice(0, index) + value.slice(index + text.length);
  return [value, previous];
}

function stringRemoveToRacerChange (segments, index, text, model) {
  var value = model._get(segments);
  var previous = value.slice(0, index) + text + value.slice(index);
  return [value, previous];
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

function patternToRegExp (pattern) {
  var regExpString = pattern
    .replace(/\./g, "\\/")
    .replace(/\*/g, "([^.]+)");
  return new RegExp(regExpString);
}

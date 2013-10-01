racer = require 'racer'
racerAccess = require '../index'
livedb = require 'livedb'
express = require 'express'
racerBrowserChannel = require 'racer-browserchannel'
http = require 'http'
racer.use racerAccess
expressApp = express()
expect = require 'expect.js'
sinon = require 'sinon'
coffeeify = require 'coffeeify'

redis = require('redis').createClient()
redis.select 8
redisObserver = require('redis').createClient()
redisObserver.select 8

store = racer.createStore
  backend: livedb.client {db:livedb.memory(), redis:redis, redisObserver:redisObserver}

store.on 'bundle', (browserify) ->
  browserify.require('racer', {expose: 'racer'})

expressApp
  .use(express.cookieParser()) # TODO Remove this?
  .use(express.session(secret: 'xyz'))
  .use((req, res, next) ->
    req.session.name = 'Brian'
    next()
  )
  .use(racerBrowserChannel(store))
  .use(store.modelMiddleware())
  .use(expressApp.router)

expressApp.listen 8000

CURR_TEST = 0

describe 'session access', ->
  before (done) ->
    redis.flushdb done

  describe 'query access control handlers', ->
    it 'should have access to the session and origin', (done) ->
      testIndex = CURR_TEST
      path = '/query'
      expressApp.get path, (req, res, next) ->
        model = req.getModel()
        query = model.query 'widgets', {}
        model.subscribe query, (err) ->
          expect(err).to.equal undefined
          res.send 200
      store.allow 'query', 'widgets', (query, session, origin, next) ->
        if testIndex is CURR_TEST
          expect(session.name).to.equal 'Brian'
          expect(origin).to.equal 'server'
        next()
        return

      req = http.request
        method: 'get'
        hostname: 'localhost'
        port: 8000
        path: path
      , (res) ->
        CURR_TEST++
        done()
      req.end()

  describe 'document access control handlers', ->
    it 'should have access to the session and origin', (done) ->
      testIndex = CURR_TEST
      path = '/doc'
      expressApp.get path, (req, res, next) ->
        model = req.getModel()
        model.fetch "widgets.#{widgetId}", (err) ->
          expect(err).to.equal undefined
          res.send 200
      store.allow 'doc', 'widgets', (docId, doc, session, origin, next) ->
        if testIndex is CURR_TEST
          expect(session.name).to.equal 'Brian'
          expect(origin).to.equal 'server'
        next()
        return

      otherModel = store.createModel()
      widgetId = otherModel.add 'widgets', {name: 'blah'}, (err) ->
        expect(err).to.equal undefined
        req = http.request
          method: 'get'
          hostname: 'localhost'
          port: 8000
          path: path
        , (res) ->
          CURR_TEST++
          done()
        req.end()

  describe 'write access control handlers', ->
    it 'should have access to the session', (done) ->
      testIndex = CURR_TEST
      path = '/write'
      expressApp.get path, (req, res, next) ->
        model = req.getModel()
        model.add 'widgets', {name: 'qbert'}, (err) ->
          expect(err).to.equal undefined
          res.send 200
      store.allow 'all', '**', (docId, relPath, opData, docBeingUpdated, session) ->
        if testIndex is CURR_TEST
          expect(session.name).to.equal 'Brian'
        return

      req = http.request
        method: 'get'
        hostname: 'localhost'
        port: 8000
        path: path
      , (res) ->
        CURR_TEST++
        done()
      req.end()

  describe 'origin detection during write access checks', ->
    it 'should know whether an op was initiated on behalf of the browser', (done) ->
      testIndex = CURR_TEST
      path = '/write_origin_browserproxy'
      expressApp.get path, (req, res, next) ->
        model = req.getModel()
        model.add 'widgets', {name: 'qbert'}, (err) ->
          expect(err).to.equal undefined
          res.send 200

      store.allow 'all', '**', (docId, relPath, opData, docBeforeChange, session) ->
        if testIndex is CURR_TEST
          expect(opData.origin).to.equal 'server'
          expect(session).to.not.equal undefined
        return

      req = http.request
        method: 'get'
        hostname: 'localhost'
        port: 8000
        path: path
      , (res) ->
        CURR_TEST++
        done()
      req.end()

    it 'should know whether the an op was initiated by the server not on behalf of the browser', (done) ->
      testIndex = CURR_TEST
      store.allow 'all', '**', (docId, relPath, opData, docBeforeChange, session) ->
        if testIndex is CURR_TEST
          expect(opData.origin).to.equal 'server'
          expect(session).to.equal undefined
        return

      model = store.createModel()
      model.add 'widgets', {name: 'qbert'}, (err) ->
        expect(err).to.equal undefined
        CURR_TEST++
        done()

    # This test requires soda and selenium-rc running on port 4444.
    it.skip 'should know whether an op was initiated by the browser', (done) ->
      @timeout 10000
      testIndex = CURR_TEST
      spy = sinon.spy()
      expressApp.get '/write_browser', (req, res, next) ->
        model = req.getModel()
        store.once 'bundle', (browserify) ->
          browserify.transform coffeeify
        store.bundle __dirname + '/client.coffee', {minify: false}, (err, storeBundle) ->
          expect(err).to.equal null
          model.bundle (err, modelBundle) ->
            expect(err).to.equal null
            res.send """
              <html>
                <body>
                  <div id=hello></div>
                </body>
                <script>
                  #{storeBundle};
                  var racer = require("racer");
                  racer.ready(function(model) {
                    model.add('widgets', {name: 'qbert'}, function (err) {
                      if (err) throw err;
                      document.getElementById("hello").innerHTML = 'Hello' + ' World';
                    });
                  });
                  racer.init(#{stringifyData(modelBundle)});
                </script>
              </html>
            """

      store.allow 'all', '**', (docId, relPath, opData, docBeforeChange, session) ->
        if testIndex is CURR_TEST
          spy()
          expect(opData.origin).to.equal 'browser'
          expect(session).to.not.equal undefined
        return

      browser = require('soda').createClient
        host: 'localhost'
        port: 4444
        url: 'http://localhost:8000'
        browser: 'googlechrome'

      browser
        .chain
        .session()
        .open('/write_browser')
        .waitForTextPresent('Hello World')
        .end (err) ->
          expect(err).to.equal null
          browser.testComplete ->
            expect(spy.calledOnce).to.equal true
            CURR_TEST++
            done()

stringifyData = (object) ->
  json = JSON.stringify object, null, 2
  return json.replace /[&']/g, (match) ->
    if (match is '&') then '&amp;' else '&#39'

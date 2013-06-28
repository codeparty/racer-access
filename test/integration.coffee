racer = require 'racer'
racerAccess = require '../index'
livedb = require 'livedb'
express = require 'express'
racerBrowserChannel = require 'racer-browserchannel'
mongoskin = require 'mongoskin'
LiveDbMongo = require 'livedb-mongo'
http = require 'http'
racer.use racerAccess
expressApp = express()
expect = require 'expect.js'

mongo = mongoskin.db('mongodb://localhost:27017/test?auto_reconnect', safe: true)
redis = require('redis').createClient()
redis.select 8
redisObserver = require('redis').createClient()
redisObserver.select 8

store = racer.createStore
  backend: livedb.client new LiveDbMongo(mongo), redis, redisObserver

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

describe 'session access', ->
  describe 'query access control handlers', ->
    it 'should have access to the session', (done) ->
      expressApp.get '/query', (req, res, next) ->
        model = req.getModel()
        query = model.query 'widgets', {}
        model.subscribe query, (err) ->
          expect(err).to.equal undefined
          res.send 200
      store.allow 'query', 'widgets', (query, session, next) ->
        expect(session.name).to.equal 'Brian'
        next()
        return

      req = http.request
        method: 'get'
        hostname: 'localhost'
        port: 8000
        path: '/query'
      , (res) -> done()
      req.end()

  describe 'document access control handlers', ->
    it 'should have access to the session', (done) ->
      expressApp.get '/doc', (req, res, next) ->
        model = req.getModel()
        query = model.query 'widgets', {}
        model.fetch 'widgets.blah', (err) ->
          expect(err).to.equal undefined
          res.send 200
      store.allow 'doc', 'widgets', (docId, doc, session, next) ->
        expect(session.name).to.equal 'Brian'
        next()
        return

      otherModel = store.createModel()
      otherModel.add 'widgets', {id: 'blah', name: 'blah'}, (err) ->
        expect(err).to.equal undefined
        req = http.request
          method: 'get'
          hostname: 'localhost'
          port: 8000
          path: '/doc'
        , (res) -> done()
        req.end()

  describe 'write access control handlers', ->
    it 'should have access to the session', (done) ->
      expressApp.get '/write', (req, res, next) ->
        model = req.getModel()
        query = model.query 'widgets', {}
        model.add 'widgets', {name: 'qbert'}, (err) ->
          expect(err).to.equal undefined
          res.send 200
      store.allow 'all', '**', (docId, relPath, opData, docBeingUpdated, session) ->
        expect(session.name).to.equal 'Brian'
        return

      req = http.request
        method: 'get'
        hostname: 'localhost'
        port: 8000
        path: '/write'
      , (res) -> done()
      req.end()

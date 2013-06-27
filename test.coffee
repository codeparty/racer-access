async = require 'async'
expect = require 'expect.js'
racer = require 'racer'
livedb = require 'livedb'
{LiveDbMongo} = require 'livedb-mongo'
mongoskin = require 'mongoskin'
mongo = mongoskin.db('mongodb://localhost:27017/test?auto_reconnect', safe: true)
redis = require('redis').createClient()
redis.select 8
redisObserver = require('redis').createClient()
redisObserver.select 8

accessPlugin = require './index'
racer.use accessPlugin

SECRET = 'shhhhhhhhhhhh'

describe 'access control on the server', ->
  beforeEach (done) ->
    @store = racer.createStore
      backend: livedb.client new LiveDbMongo(mongo), redis, redisObserver

    mongo.dropDatabase =>
      redis.flushdb =>
        @model = @store.createModel()
        done()

  after (done) ->
    async.parallel [
      (parallelCb) -> mongo.close parallelCb
      (parallelCb) -> redis.quit parallelCb
      (parallelCb) -> redisObserver.quit parallelCb
    ], done

  describe 'read access', ->
    describe 'for queries', ->
      beforeEach ->
        @store.allow 'query', 'widgets', (query, session, next) ->
          if query.secret is SECRET
            next()
          else
            next('Unauthorized')

      it 'should allow permissible queries', (done) ->
        query = @model.query 'widgets', {secret: SECRET}
        @model.subscribe query, (err) ->
          expect(err).to.equal undefined
          done()

      it 'should block non-permissible queries', (done) ->
        query = @model.query 'widgets', {secret: 'not' + SECRET}
        @model.subscribe query, (err) ->
          expect(err).to.equal 'Unauthorized'
          done()

    describe 'for docs', ->
      beforeEach ->
        @store.allow 'doc', 'widgets', (docId, doc, session, next) ->
          if doc.secret is SECRET
            next()
          else
            next('Unauthorized')
        @publicWidgetId

      it 'should allow permissible docs', (done) ->
        model = @store.createModel()
        widgetId = model.add 'widgets', {secret: SECRET}, (err) =>
          @model.subscribe "widgets.#{widgetId}", (err) ->
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible docs', (done) ->
        model = @store.createModel()
        widgetId = model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
          @model.subscribe "widgets.#{widgetId}", (err) ->
            expect(err).to.equal 'Unauthorized'
            done()

  describe 'write access', ->
    describe 'on "change"', ->
      describe 'via document creation', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.name', (docId, changeTo, docBeforeChange, apply, session, allow) ->
            if docBeforeChange
              if docBeforeChange.secret is SECRET
                allow()
              else
                allow('Unauthorized')
            else
              if changeTo.secret is SECRET
                allow()
              else
                allow('Unauthorized')

        it 'should allow permissible changes', (done) ->
          @model.add 'widgets', {secret: SECRET}, (err) =>
            expect(err).to.equal undefined
            done()

        it 'should block non-permissible changes', (done) ->
          @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
            expect(err).to.equal 'Unauthorized'
            done()

      describe 'via set on document', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.name', (docId, changeTo, docBeforeChange, apply, session, allow) ->
            if docBeforeChange
              if docBeforeChange.secret is SECRET
                allow()
              else
                allow('Unauthorized')
            else
              allow() # Allow all creations

        it 'should allow permissible changes', (done) ->
          model = @store.createModel()
          widgetId = model.add 'widgets', {secret: SECRET}, (err) =>
            expect(err).to.equal undefined
            @model.fetch "widgets.#{widgetId}", (err) =>
              @model.set "widgets.#{widgetId}.name", 'Brian', (err) ->
                expect(err).to.equal undefined
                done()

        it 'should block non-permissible changes', (done) ->
          model = @store.createModel()
          widgetId = model.add 'widgets', {secret: 'non' + SECRET}, (err) =>
            expect(err).to.equal undefined
            @model.fetch "widgets.#{widgetId}", (err) =>
              @model.set "widgets.#{widgetId}.name", 'Brian', (err) ->
                expect(err).to.equal 'Unauthorized'
                done()


    describe 'on "create"', ->
      beforeEach ->
        @store.allow 'create', 'widgets', (docId, newDoc, session, allow) ->
          if newDoc.secret is SECRET
            allow()
          else
            allow('Unauthorized')

      it 'should allow permissible changes', (done) ->
        @model.add 'widgets', {secret: SECRET}, (err) =>
          expect(err).to.equal undefined
          done()

      it 'should block non-permissible changes', (done) ->
        @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
          expect(err).to.equal 'Unauthorized'
          done()

    describe 'on "remove"', ->
      beforeEach ->
        @store.allow 'remove', 'widgets.*.list', (docId, index, howMany, docBeforeChange, apply, session, allow) ->
          if docBeforeChange.secret is SECRET
            allow()
          else
            allow('Unauthorized')

      it 'should allow permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b', 'c']}, (err) =>
          expect(err).to.equal undefined
          @model.remove "widgets.#{widgetId}.list", 0, 2, (err) =>
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b', 'c']}, (err) =>
          expect(err).to.equal undefined
          @model.remove "widgets.#{widgetId}.list", 0, 2, (err) =>
            expect(err).to.equal 'Unauthorized'
            done()

    describe 'on "insert"', ->
      beforeEach ->
        @store.allow 'insert', 'widgets.*.list', (docId, index, elements, docBeforeInsert, apply, session, allow) ->
          if docBeforeChange.secret is SECRET
            allow()
          else
            allow('Unauthorized')

      it 'should allow permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
          @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
          @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
            expect(err).to.equal 'Unauthorized'
            done()

    describe 'on "del"', ->
      it 'should allow permissible deletes'
      it 'should block non-permissible deletes'

    describe 'on "all"', ->
      it 'should allow permissible changes'
      it 'should block non-permissible changes'

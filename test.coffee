async = require 'async'
expect = require 'expect.js'
racer = require 'racer'
livedb = require 'livedb'
{LiveDbMongo} = require 'livedb-mongo'
mongoskin = require 'mongoskin'

accessPlugin = require './index'
racer.use accessPlugin

SECRET = 'shhhhhhhhhhhh'

describe 'access control on the server', ->
  beforeEach (done) ->
    @mongo = mongoskin.db('mongodb://localhost:27017/test?auto_reconnect', safe: true)
    @redis = require('redis').createClient()
    @redis.select 8
    @redisObserver = require('redis').createClient()
    @redisObserver.select 8
    @store = racer.createStore
      backend: livedb.client new LiveDbMongo(@mongo), @redis, @redisObserver

    @mongo.dropDatabase =>
      @redis.flushdb =>
        @model = @store.createModel()
        done()

  afterEach (done) ->
    async.parallel [
      (parallelCb) => @mongo.close parallelCb
      (parallelCb) => @redis.quit parallelCb
      (parallelCb) => @redisObserver.quit parallelCb
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
          @store.allow 'change', 'widgets.*', (docId, newDoc, docBeforeChange, session) ->
            return 'Unauthorized' if newDoc.secret isnt SECRET

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
          @store.allow 'change', 'widgets.*.name', (docId, changeTo, docBeforeChange, sessio) ->
            return 'Unauthorized' if docBeforeChange && docBeforeChange.secret isnt SECRET

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

      describe 'via increment on a document', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.age', (docId, incrBy, docBeforeIncrement, session) ->
            return unless docBeforeIncrement
            return 'Unauthorized' if docBeforeIncrement.secret isnt SECRET

        it 'should allow permissible changes', (done) ->
          model = @store.createModel()
          widgetId = model.add 'widgets', {secret: SECRET}, (err) =>
            expect(err).to.equal undefined
            @model.fetch "widgets.#{widgetId}", (err) =>
              @model.increment "widgets.#{widgetId}.age", 21, (err) ->
                expect(err).to.equal undefined
                done()

        it 'should block non-permissible changes', (done) ->
          model = @store.createModel()
          widgetId = model.add 'widgets', {secret: 'non' + SECRET}, (err) =>
            expect(err).to.equal undefined
            @model.fetch "widgets.#{widgetId}", (err) =>
              @model.increment "widgets.#{widgetId}.age", 21, (err) ->
                expect(err).to.equal 'Unauthorized'
                done()

      describe 'via del on a document attribute', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.toDel', (docId, incrBy, docBeforeDel, session) ->
            return unless docBeforeDel
            return 'Unauthorized' if docBeforeDel.secret isnt SECRET

        it 'should allow permissible changes', (done) ->
          model = @store.createModel()
          widgetId = model.add 'widgets', {secret: SECRET, toDel: 'x'}, (err) =>
            expect(err).to.equal undefined
            @model.fetch "widgets.#{widgetId}", (err) =>
              @model.del "widgets.#{widgetId}.toDel", (err) ->
                expect(err).to.equal undefined
                done()

        it 'should block non-permissible changes', (done) ->
          model = @store.createModel()
          widgetId = model.add 'widgets', {secret: 'not' + SECRET, toDel: 'x'}, (err) =>
            expect(err).to.equal undefined
            @model.fetch "widgets.#{widgetId}", (err) =>
              @model.del "widgets.#{widgetId}.toDel", (err) ->
                expect(err).to.equal 'Unauthorized'
                done()

      describe 'via replacing a list on a document', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.list.*', (docId, index, changeTo, docBeforeInsert, session) ->
            return 'Unauthorized' if docBeforeInsert.secret isnt SECRET

        it 'should allow permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b']}, (err) =>
            expect(err).to.equal undefined
            @model.set "widgets.#{widgetId}.list.0", 'x', (err) =>
              expect(err).to.equal undefined
              done()

        it 'should block non-permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b']}, (err) =>
            expect(err).to.equal undefined
            @model.set "widgets.#{widgetId}.list.0", 'x', (err) =>
              expect(err).to.equal undefined
              done()

      describe 'via stringInsert', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.text', (docId, changeTo, docBeforeChange, session) ->
            return 'Unauthorized' if docBeforeChange.secret isnt SECRET

        it 'should allow permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: SECRET, text: 'abc'}, (err) =>
            expect(err).to.equal undefined
            @model.stringInsert "widgets.#{widgetId}.text", 1, 'xyz', (err) =>
              expect(err).to.equal undefined
              done()

        it 'should block non-permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: 'not' + SECRET, text: 'abc'}, (err) =>
            expect(err).to.equal undefined
            @model.stringInsert "widgets.#{widgetId}.text", 1, 'xyz', (err) =>
              expect(err).to.equal 'Unauthorized'
              done()

      describe 'via stringRemove', ->


    describe 'on "create"', ->
      beforeEach ->
        @store.allow 'create', 'widgets', (docId, newDoc, session) ->
          return 'Unauthorized' if newDoc.secret isnt SECRET

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
        @store.allow 'remove', 'widgets.*.list', (docId, index, howMany, docBeforeChange, session) ->
          return 'Unauthorized' if docBeforeChange.secret isnt SECRET

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
        @store.allow 'insert', 'widgets.*.list', (docId, index, elements, docBeforeInsert, session) ->
          return 'Unauthorized' if docBeforeInsert.secret isnt SECRET

      it 'should allow permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
          expect(err).to.equal undefined
          @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
          expect(err).to.equal undefined
          @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
            expect(err).to.equal 'Unauthorized'
            done()

    describe 'on "move"', ->

    # TODO 'destroy'
    describe 'on "del"', ->
      beforeEach ->
        @store.allow 'del', 'widgets', (docId, docToRemove, session) ->
          return 'Unauthorized' if docToRemove.secret isnt SECRET

        @store.allow 'del', 'widgets.*.toDel', (docId, valueToDel, docBeforeDel, session) ->
          return 'Unauthorized' if docBeforeDel.secret isnt SECRET

      it 'should allow permissible document deletes zzz', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
          expect(err).to.equal undefined
          @model.del "widgets.#{widgetId}", (err) =>
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible document deletes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
          expect(err).to.equal undefined
          @model.del "widgets.#{widgetId}", (err) =>
            expect(err).to.equal undefined
            done()

      it 'should allow permissible attribute deletes', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET, toDel: 'x'}, (err) =>
          expect(err).to.equal undefined
          @model.del "widgets.#{widgetId}.toDel", (err) =>
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible attribute deletes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET, toDel: 'x'}, (err) =>
          expect(err).to.equal undefined
          @model.del "widgets.#{widgetId}.toDel", (err) =>
            expect(err).to.equal 'Unauthorized'
            done()

      it 'should not fire for other changes that are not del', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET, toDel: 'x'}, (err) =>
          expect(err).to.equal undefined
          @model.set "widgets.#{widgetId}.toDel", 'y', (err) =>
            expect(err).to.equal undefined
            done()

    describe 'on "all"', ->
      it 'should allow permissible changes'
      it 'should block non-permissible changes'

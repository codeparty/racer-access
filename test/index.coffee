# TODO
# - Test parameters
# - Test existence of session as a parameter
# - Test subtree patterns (i.e., xyz.*.a.b.c**)
# - Should access control "change" ruls on subpaths impact a model.add ?
async = require 'async'
expect = require 'expect.js'
sinon = require 'sinon'
racer = require 'racer'
livedb = require 'livedb'

accessPlugin = require '../index'
racer.use accessPlugin

SECRET = 'shhhhhhhhhhhh'

shouldAllowAndBlockForAll = ->
  describe 'caused by doc creation', ->
    it 'should allow permissible changes', (done) ->
      @model.add 'widgets', {secret: SECRET}, (err) =>
        expect(err).to.equal undefined
        done()

    it 'should block non-permissible changes', (done) ->
      @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
        expect(err).to.equal 'Unauthorized'
        done()

  describe 'caused by doc attribute setting', ->
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
      widgetId = model.add 'widgets', {secret: 'not' + SECRET, admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.fetch "widgets.#{widgetId}", (err) =>
          @model.set "widgets.#{widgetId}.name", 'Brian', (err) ->
            expect(err).to.equal 'Unauthorized'
            done()

  describe 'caused by increment', ->
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
      widgetId = model.add 'widgets', {secret: 'non' + SECRET, admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.fetch "widgets.#{widgetId}", (err) =>
          @model.increment "widgets.#{widgetId}.age", 21, (err) ->
            expect(err).to.equal 'Unauthorized'
            done()

  describe 'caused by document destruction', ->
    it 'should allow permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
        expect(err).to.equal undefined
        @model.del "widgets.#{widgetId}", (err) =>
          expect(err).to.equal undefined
          done()
    it 'should block non-permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.del "widgets.#{widgetId}", (err) =>
          expect(err).to.equal 'Unauthorized'
          done()

  describe 'caused by document attribute deletion', ->
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
      widgetId = model.add 'widgets', {secret: 'not' + SECRET, toDel: 'x', admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.fetch "widgets.#{widgetId}", (err) =>
          @model.del "widgets.#{widgetId}.toDel", (err) ->
            expect(err).to.equal 'Unauthorized'
            done()

  describe 'caused by list element replacement', ->
    it 'should allow permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b']}, (err) =>
        expect(err).to.equal undefined
        @model.set "widgets.#{widgetId}.list.0", 'x', (err) =>
          expect(err).to.equal undefined
          done()

    it 'should block non-permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b'], admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.set "widgets.#{widgetId}.list.0", 'x', (err) =>
          expect(err).to.equal 'Unauthorized'
          done()

  describe 'caused by stringInsert', ->
    it 'should allow permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET, text: 'abc'}, (err) =>
        expect(err).to.equal undefined
        @model.stringInsert "widgets.#{widgetId}.text", 1, 'xyz', (err) =>
          expect(err).to.equal undefined
          done()

    it 'should block non-permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, text: 'abc', admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.stringInsert "widgets.#{widgetId}.text", 1, 'xyz', (err) =>
          expect(err).to.equal 'Unauthorized'
          done()

  describe 'caused by stringRemove', ->
    it 'should allow permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET, text: 'abc'}, (err) =>
        expect(err).to.equal undefined
        @model.stringRemove "widgets.#{widgetId}.text", 1, 1, (err) =>
          expect(err).to.equal undefined
          done()
    it 'should block non-permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, text: 'abc', admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.stringRemove "widgets.#{widgetId}.text", 1, 1, (err) =>
          expect(err).to.equal 'Unauthorized'
          done()
  describe 'caused by removing items from a list', ->
    it 'should allow permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b', 'c']}, (err) =>
        expect(err).to.equal undefined
        @model.remove "widgets.#{widgetId}.list", 0, 2, (err) =>
          expect(err).to.equal undefined
          done()

    it 'should block non-permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b', 'c'], admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.remove "widgets.#{widgetId}.list", 0, 2, (err) =>
          expect(err).to.equal 'Unauthorized'
          done()

  describe 'caused by inserting items into a list', ->
    it 'should allow permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
        expect(err).to.equal undefined
        @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
          expect(err).to.equal undefined
          done()

    it 'should block non-permissible changes', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
          expect(err).to.equal 'Unauthorized'
          done()
  describe 'caused by moving items in a list', ->
    it 'should allow permissible moves', (done) ->
      widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b', 'c']}, (err) =>
        expect(err).to.equal undefined
        @model.move "widgets.#{widgetId}.list", 0, 1, 1, (err) =>
          expect(err).to.equal undefined
          done()
    it 'should block non-permissible moves', (done) ->
      widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b', 'c'], admin: true}, (err) =>
        expect(err).to.equal undefined
        @model.move "widgets.#{widgetId}.list", 0, 1, 1, (err) =>
          expect(err).to.equal 'Unauthorized'
          done()

describe 'access control on the server', ->
  beforeEach (done) ->
    @redis = require('redis').createClient()
    @redis.select 8
    @redisObserver = require('redis').createClient()
    @redisObserver.select 8
    @store = racer.createStore
      backend: livedb.client
        db: livedb.memory()
        redis: @redis
        redisObserver: @redisObserver

    @redis.flushdb =>
      @model = @store.createModel()
      done()

  afterEach (done) ->
    async.parallel [
      (parallelCb) => @redis.quit parallelCb
      (parallelCb) => @redisObserver.quit parallelCb
    ], done

  describe 'read access', ->
    describe 'for queries', ->
      beforeEach ->
        @store.allow 'query', 'widgets', (query, session, origin, next) ->
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
        @store.allow 'doc', 'widgets', (docId, doc, session, origin, next) ->
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

      describe 'via list element replacement', ->
        beforeEach ->
          @store.allow 'change', 'widgets.*.list.*', (docId, index, changeTo, docBeforeInsert, session) ->
            return 'Unauthorized' if docBeforeInsert.secret isnt SECRET

        it 'should allow permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b']}, (err) =>
            expect(err).to.equal undefined
            @model.set "widgets.#{widgetId}.list.0", 'x', (err) =>
              expect(err).to.equal undefined
              @model.set "widgets.#{widgetId}.list.0", '', (err) =>
                expect(err).to.equal undefined
                done()

        it 'should block non-permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b']}, (err) =>
            expect(err).to.equal undefined
            @model.set "widgets.#{widgetId}.list.0", 'x', (err) =>
              expect(err).to.equal 'Unauthorized'
              @model.set "widgets.#{widgetId}.list.0", '', (err) =>
                expect(err).to.equal 'Unauthorized'
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
        beforeEach ->
          @store.allow 'change', 'widgets.*.text', (docId, changeTo, docBeforeChange, session) ->
            return 'Unauthorized' if docBeforeChange.secret isnt SECRET

        it 'should allow permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: SECRET, text: 'abc'}, (err) =>
            expect(err).to.equal undefined
            @model.stringRemove "widgets.#{widgetId}.text", 1, 1, (err) =>
              expect(err).to.equal undefined
              done()

        it 'should block non-permissible changes', (done) ->
          widgetId = @model.add 'widgets', {secret: 'not' + SECRET, text: 'abc'}, (err) =>
            expect(err).to.equal undefined
            @model.stringRemove "widgets.#{widgetId}.text", 1, 1, (err) =>
              expect(err).to.equal 'Unauthorized'
              done()

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
        widgetId = @model.add 'widgets', {secret: SECRET, list:[]}, (err) =>
          expect(err).to.equal undefined
          @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
            expect(err).to.equal undefined
            @model.insert "widgets.#{widgetId}.list", 2, [0], (err) =>
              expect(err).to.equal undefined
              done()

      it 'should block non-permissible changes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list:[]}, (err) =>
          expect(err).to.equal undefined
          @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
            expect(err).to.equal 'Unauthorized'
            @model.insert "widgets.#{widgetId}.list", 0, [0], (err) =>
              expect(err).to.equal 'Unauthorized'
              done()

    describe 'on "move"', ->
      beforeEach ->
        @store.allow 'move', 'widgets.*.list', (docId, from, to, howMany, docBeforeInsert, session) ->
          return 'Unauthorized' if docBeforeInsert.secret isnt SECRET

      it 'should allow permissible moves', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b', 'c']}, (err) =>
          expect(err).to.equal undefined
          @model.move "widgets.#{widgetId}.list", 0, 1, 1, (err) =>
            expect(err).to.equal undefined
            done()
      it 'should block non-permissible moves', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b', 'c']}, (err) =>
          expect(err).to.equal undefined
          @model.move "widgets.#{widgetId}.list", 0, 1, 1, (err) =>
            expect(err).to.equal 'Unauthorized'
            done()

    # TODO 'destroy'
    describe 'on "del"', ->
      beforeEach ->
        @store.allow 'del', 'widgets', (docId, docToRemove, session) ->
          return 'Unauthorized' if docToRemove.secret isnt SECRET

        @store.allow 'del', 'widgets.*.toDel', (docId, valueToDel, docBeforeDel, session) ->
          return 'Unauthorized' if docBeforeDel.secret isnt SECRET

      it 'should allow permissible document deletes', (done) ->
        widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
          expect(err).to.equal undefined
          @model.del "widgets.#{widgetId}", (err) =>
            expect(err).to.equal undefined
            done()

      it 'should block non-permissible document deletes', (done) ->
        widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
          expect(err).to.equal undefined
          @model.del "widgets.#{widgetId}", (err) =>
            expect(err).to.equal 'Unauthorized'
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
      describe 'for all ops on all collections', ->
        beforeEach ->
          @store.allow 'all', '**', (docId, relPath, opData, docBeingUpdated, connectSession) ->
            unless docBeingUpdated
              newDoc = opData.create.data
              return 'Unauthorized' if !newDoc.admin && newDoc.secret isnt SECRET
            else
              return 'Unauthorized' if docBeingUpdated.secret isnt SECRET

        shouldAllowAndBlockForAll()

      describe 'for all ops on a collection', ->
        beforeEach ->
          @store.allow 'all', 'widgets**', (docId, relPath, opData, docBeingUpdated, session) ->
            unless docBeingUpdated
              newDoc = opData.create.data
              return 'Unauthorized' if !newDoc.admin && newDoc.secret isnt SECRET
            else
              return 'Unauthorized' if docBeingUpdated.secret isnt SECRET

        shouldAllowAndBlockForAll()

      describe 'for all ops on a particular path', ->
        beforeEach ->
          @store.allow 'all', 'widgets.*.age', (docId, relPath, opData, docBeingUpdated, session) ->
            expect(relPath).to.equal 'age'
            return 'Unauthorized' if docBeingUpdated.secret isnt SECRET

        it 'should not block operations that do not match the path', (done) ->
          widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
            expect(err).to.equal undefined
            done()

        describe 'attribute setting', ->
          it 'should allow permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
              expect(err).to.equal undefined
              @model.set "widgets.#{widgetId}.name", 28, (err) ->
                expect(err).to.equal undefined
                done()

          it 'should block non-permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
              expect(err).to.equal undefined
              @model.set "widgets.#{widgetId}.age", 28, (err) ->
                expect(err).to.equal 'Unauthorized'
                done()

        describe 'caused by increment', ->
          it 'should allow permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
              expect(err).to.equal undefined
              @model.increment "widgets.#{widgetId}.age", 28, (err) ->
                expect(err).to.equal undefined
                done()

          it 'should block non-permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: 'not' + SECRET}, (err) =>
              expect(err).to.equal undefined
              @model.increment "widgets.#{widgetId}.age", 28, (err) ->
                expect(err).to.equal 'Unauthorized'
                done()

        describe 'delete an attribute', ->
          it 'should allow permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: SECRET, age: 22}, (err) =>
              expect(err).to.equal undefined
              @model.del "widgets.#{widgetId}.age", (err) ->
                expect(err).to.equal undefined
                done()

          it 'should block non-permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: 'not' + SECRET, age: 22}, (err) =>
              expect(err).to.equal undefined
              @model.del "widgets.#{widgetId}.age", (err) ->
                expect(err).to.equal 'Unauthorized'
                done()

        describe 'caused by list element replacement', ->
          beforeEach ->
            @store.allow 'all', 'widgets.*.list.*', (docId, relPath, opData, docBeforeReplace, session) ->
              return 'Unauthorized' if docBeforeReplace.secret isnt SECRET

          it 'should allow permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b']}, (err) =>
              expect(err).to.equal undefined
              @model.set "widgets.#{widgetId}.list.0", 'x', (err) ->
                expect(err).to.equal undefined
                done()

          it 'should block non-permissible changes', (done) ->
            widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b']}, (err) =>
              expect(err).to.equal undefined
              @model.set "widgets.#{widgetId}.list.0", 'x', (err) ->
                expect(err).to.equal 'Unauthorized'
                done()

        describe 'caused by stringInsert/stringRemove', ->
          beforeEach ->
            @store.allow 'all', 'widgets.*.text', (docId, relPath, opData, docBeforeReplace, session) ->
              return 'Unauthorized' if docBeforeReplace.secret isnt SECRET
          describe 'caused by stringInsert', ->
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

          describe 'caused by stringRemove', ->
            it 'should allow permissible changes', (done) ->
              widgetId = @model.add 'widgets', {secret: SECRET, text: 'abc'}, (err) =>
                expect(err).to.equal undefined
                @model.stringRemove "widgets.#{widgetId}.text", 1, 1, (err) =>
                  expect(err).to.equal undefined
                  done()
            it 'should block non-permissible changes', (done) ->
              widgetId = @model.add 'widgets', {secret: 'not' + SECRET, text: 'abc'}, (err) =>
                expect(err).to.equal undefined
                @model.stringRemove "widgets.#{widgetId}.text", 1, 1, (err) =>
                  expect(err).to.equal 'Unauthorized'
                  done()

        describe 'insert, remove, move in a list', ->
          beforeEach ->
            @store.allow 'all', 'widgets.*.list', (docId, relPath, opData, docBeforeReplace, session) ->
              return 'Unauthorized' if docBeforeReplace.secret isnt SECRET
          describe 'caused by removing items from a list', ->
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
          describe 'caused by inserting items into a list', ->
            it 'should allow permissible changes', (done) ->
              widgetId = @model.add 'widgets', {secret: SECRET}, (err) =>
                expect(err).to.equal undefined
                @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
                  expect(err).to.equal undefined
                  done()

            it 'should block non-permissible changes', (done) ->
              widgetId = @model.add 'widgets', {secret: 'not' + SECRET, admin: true}, (err) =>
                expect(err).to.equal undefined
                @model.insert "widgets.#{widgetId}.list", 0, ['a', 'b'], (err) =>
                  expect(err).to.equal 'Unauthorized'
                  done()
          describe 'caused by moving items in a list', ->
            it 'should allow permissible moves', (done) ->
              widgetId = @model.add 'widgets', {secret: SECRET, list: ['a', 'b', 'c']}, (err) =>
                expect(err).to.equal undefined
                @model.move "widgets.#{widgetId}.list", 0, 1, 1, (err) =>
                  expect(err).to.equal undefined
                  done()
            it 'should block non-permissible moves', (done) ->
              widgetId = @model.add 'widgets', {secret: 'not' + SECRET, list: ['a', 'b', 'c'], admin: true}, (err) =>
                expect(err).to.equal undefined
                @model.move "widgets.#{widgetId}.list", 0, 1, 1, (err) =>
                  expect(err).to.equal 'Unauthorized'
                  done()

      describe 'for all ops on a particular subtree', ->
        describe 'caused by doc creation', ->
        describe 'caused by doc attribute setting', ->
        describe 'caused by increment', ->
        describe 'caused by document destruction', ->
        describe 'caused by document attribute deletion', ->
        describe 'caused by list element replacement', ->
        describe 'caused by stringInsert', ->
        describe 'caused by stringRemove', ->
        describe 'caused by removing items from a list', ->
        describe 'caused by inserting items into a list', ->
        describe 'caused by moving items in a list', ->

  describe 'access to parameters in store.allow callbacks', ->
    describe 'for "query"', ->
      it 'should have access to the query and the origin', (done) ->
        spy = sinon.spy()
        @store.allow 'query', 'widgets', (query, session, origin, next) ->
          expect(query).to.eql queryObject
          expect(origin).to.equal 'server'
          spy()
          next()

        queryObject = {name: 'qbert'}
        @model.subscribe @model.query('widgets', queryObject), (err) ->
          expect(err).to.equal undefined
          expect(spy.calledOnce).to.equal true
          done()

      describe 'with **', ->
        it 'should have access to the collection, query, and origin', (done) ->
          spy = sinon.spy()
          @store.allow 'query', '**', (collection, query, session, origin, next) ->
            expect(collection).to.equal 'widgets'
            expect(query).to.eql queryObject
            expect(origin).to.equal 'server'
            spy()
            next()

          queryObject = {name: 'qbert'}
          @model.subscribe @model.query('widgets', queryObject), (err) ->
            expect(err).to.equal undefined
            expect(spy.calledOnce).to.equal true
            done()

    describe 'for "doc"', ->
      it 'should have access to docId, doc, and origin', (done) ->
        spy = sinon.spy()
        @store.allow 'doc', 'widgets', (docId, doc, session, origin, next) ->
          expect(docId).to.equal widgetId
          expect(doc).to.eql newDoc
          expect(origin).to.equal 'server'
          spy()
          next()

        otherModel = @store.createModel()

        newDoc = {name: 'qbert'}
        widgetId = otherModel.add 'widgets', newDoc, (err) =>
          expect(err).to.equal undefined
          @model.subscribe "widgets.#{widgetId}", (err) ->
            expect(err).to.equal undefined
            expect(spy.calledOnce).to.equal true
            done()

      describe 'with **', ->
        it 'should have access to collection, docId, doc, and origin', (done) ->
          spy = sinon.spy()
          @store.allow 'doc', '**', (collection, docId, doc, session, origin, next) ->
            expect(collection).to.equal 'widgets'
            expect(docId).to.equal widgetId
            expect(doc).to.eql newDoc
            expect(origin).to.equal 'server'
            spy()
            next()

          otherModel = @store.createModel()

          newDoc = {name: 'qbert'}
          widgetId = otherModel.add 'widgets', newDoc, (err) =>
            expect(err).to.equal undefined
            @model.subscribe "widgets.#{widgetId}", (err) ->
              expect(err).to.equal undefined
              expect(spy.calledOnce).to.equal true
              done()

    describe 'for "create"', ->
      it 'should have access to docId and newDoc', (done) ->
        spy = sinon.spy()
        @store.allow 'create', 'widgets', (docId, newDoc, session) ->
          expect(docId).to.equal widgetId
          expect(newDoc).to.eql widget
          spy()
          return

        widget = {name: 'qbert'}
        widgetId = @model.add 'widgets', widget, (err) ->
          expect(err).to.equal undefined
          expect(spy.calledOnce).to.equal true
          done()

    describe 'for "change"', ->
      it 'should have access to docId, newValue, docBeforeChange', (done) ->
        spy = sinon.spy()
        @store.allow 'change', 'widgets.*.name', (docId, newValue, docBeforeChange, session) ->
          expect(docId).to.equal widgetId
          expect(newValue).to.equal 'qbot'
          expect(docBeforeChange.name).to.equal 'qbert'
          expect(docBeforeChange).to.eql {id: widgetId, name: 'qbert'}
          spy()
          return
        widget = {name: 'qbert'}
        widgetId = @model.add 'widgets', widget, (err) =>
          expect(err).to.equal undefined
          @model.set "widgets.#{widgetId}.name", 'qbot', (err) ->
            expect(err).to.equal undefined
            expect(spy.calledOnce).to.equal true
            done()

      describe 'with > 1 "*"s in the pattern', ->
        it 'should have access to docId, captures, newValue, docBeforeChange', (done) ->
          spy = sinon.spy()
          @store.allow 'change', 'widgets.*.list.*.name', (docId, listIndex, newValue, docBeforeChange, session) ->
            expect(docId).to.equal widgetId
            expect(listIndex).to.equal 0
            expect(newValue).to.equal 'qbot'
            expect(docBeforeChange.list[0].name).to.equal 'qbert'
            expect(docBeforeChange).to.eql {id: widgetId, list: [{name: 'qbert'}]}
            spy()
            return
          widget = {list: [{name: 'qbert'}]}
          widgetId = @model.add 'widgets', widget, (err) =>
            expect(err).to.equal undefined
            @model.set "widgets.#{widgetId}.list.0.name", 'qbot', (err) ->
              expect(err).to.equal undefined
              expect(spy.calledOnce).to.equal true
              done()

    describe 'for "insert"', ->
      it 'should have access to docId, index, elementsToInsert, docBeforeInsert', (done) ->
        spy = sinon.spy()
        @store.allow 'insert', 'widgets.*.list', (docId, index, elementsToInsert, docBeforeInsert, session) ->
          spy()
          expect(docId).to.equal widgetId
          if spy.callCount is 1
            expect(index).to.equal 1
            expect(elementsToInsert).to.eql ['a']
            expect(docBeforeInsert.list).to.eql ['x', 'y']
          if spy.callCount is 2
            expect(index).to.equal 2
            expect(elementsToInsert).to.eql ['b']
            expect(docBeforeInsert.list).to.eql ['x', 'a', 'y']
          return
        widgetId = @model.add 'widgets', {list: ['x', 'y']}, (err) =>
          expect(err).to.equal undefined
          @model.insert "widgets.#{widgetId}.list", 1, ['a', 'b'], (err) ->
            expect(err).to.equal undefined
            expect(spy.callCount).to.equal 2
            done()

    describe 'for "remove"', ->
      it 'should have access to docId, index, howMany, docBeforeRemove', (done) ->
        spy = sinon.spy()
        @store.allow 'remove', 'widgets.*.list', (docId, index, howMany, docBeforeRemove, session) ->
          spy()
          expect(docId).to.equal widgetId
          if spy.callCount is 1
            expect(index).to.equal 1
            expect(howMany).to.equal 1
            expect(docBeforeRemove.list).to.eql ['x', 'y', 'z']
          if spy.callCount is 2
            expect(index).to.equal 1
            expect(howMany).to.equal 1
            expect(docBeforeRemove.list).to.eql ['x', 'z']
          return
        widgetId = @model.add 'widgets', {list: ['x', 'y', 'z']}, (err) =>
          expect(err).to.equal undefined
          @model.remove "widgets.#{widgetId}.list", 1, 2, (err) ->
            expect(err).to.equal undefined
            expect(spy.callCount).to.equal 2
            done()
    describe 'for "move"', ->
      it 'should have access to docId, fromm, to, howMany, docBeforeInsert', (done) ->
        spy = sinon.spy()
        @store.allow 'move', 'widgets.*.list', (docId, from, to, howMany, docBeforeMove, session) ->
          spy()
          expect(docId).to.equal widgetId
          if spy.callCount is 1
            expect(from).to.equal 1
            expect(to).to.equal 3
            expect(howMany).to.equal 1
            expect(docBeforeMove.list).to.eql ['w', 'x', 'y', 'z']
          if spy.callCount is 2
            # expect(from).to.equal 1
            expect(from).to.equal 1
            expect(to).to.equal 3
            expect(howMany).to.equal 1
            expect(docBeforeMove.list).to.eql ['w', 'y', 'z', 'x']
          return
        widgetId = @model.add 'widgets', {list: ['w', 'x', 'y', 'z']}, (err) =>
          expect(err).to.equal undefined
          @model.move "widgets.#{widgetId}.list", 1, 3, 2, (err) =>
            expect(err).to.equal undefined
            expect(@model.get "widgets.#{widgetId}.list").to.eql ['w', 'z', 'x', 'y']
            expect(spy.callCount).to.equal 2
            done()
    describe 'for "del"', ->
      describe 'deleting documents', ->
        it 'should have access to docId, docToRemove,', (done) ->
          spy = sinon.spy()
          @store.allow 'del', 'widgets', (docId, docToRemove, session) ->
            spy()
            expect(docId).to.equal widgetId
            expect(docToRemove).to.eql {id: widgetId, name: 'qbert'}
            return
          widget = {name: 'qbert'}
          widgetId = @model.add 'widgets', widget, (err) =>
            expect(err).to.equal undefined
            @model.del "widgets.#{widgetId}", (err) ->
              expect(err).to.equal undefined
              expect(spy.calledOnce).to.equal true
              done()

      describe 'deleting attributes', ->
        it 'should have access to docId, valueToDel, docBeforeDel', (done) ->
          spy = sinon.spy()
          @store.allow 'del', 'widgets.*.toDel', (docId, valueToDel, docBeforeDel, session) ->
            spy()
            expect(docId).to.equal widgetId
            expect(valueToDel).to.equal 'qbert'
            expect(docBeforeDel).to.eql {id: widgetId, name: 'qbert'}
            return
          widget = {name: 'qbert'}
          widgetId = @model.add 'widgets', widget, (err) =>
            expect(err).to.equal undefined
            @model.del "widgets.#{widgetId}.name", (err) ->
              expect(err).to.equal undefined
              expect(spy.calledOnce).to.equal true
              done()

    describe 'for "all"', ->
      ['**', 'widgets**'].forEach (pattern) ->
        describe "for '#{pattern}'", ->
          it 'should have access to docId, relPath, opData, docBeingUpdated', (done) ->
            spy = sinon.spy()
            @store.allow 'all', pattern, (docId, relPath, opData, docBeingUpdated, session) ->
              spy()
              expect(docId).to.equal widgetId
              if spy.callCount is 1
                expect(relPath).to.equal ''
                expect(opData.create).to.be.ok()
                expect(docBeingUpdated).to.equal undefined
              if spy.callCount is 2
                expect(relPath).to.equal 'name'
                expect(docBeingUpdated).to.eql {id: widgetId, name: 'qbert'}
              return
            widget = {name: 'qbert'}
            widgetId = @model.add 'widgets', widget, (err) =>
              expect(err).to.equal undefined
              @model.set "widgets.#{widgetId}.name", 'qbot', (err) ->
                expect(err).to.equal undefined
                expect(spy.callCount).to.equal 2
                done()

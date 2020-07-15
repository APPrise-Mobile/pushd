events = require 'events'
Payload = require('./payload').Payload
logger = require 'winston'

class EventPublisher extends events.EventEmitter
    constructor: (@pushServices) ->

    publish: (event, data, cb) ->
        try
            payload = new Payload(data)
            payload.event = event
        catch e
            # Invalid payload (empty, missing key or invalid key format)
            logger.error 'Invalid payload ' + e
            cb(-1) if cb
            return

        @.emit(event.name, event, payload)

        event.exists (exists) =>
            if not exists
                logger.verbose "Tried to publish to a non-existing userID #{event.name}"
                cb(0) if cb
                return

            try
                # Do not compile templates before to know there's some subscribers for the event
                # and do not start serving subscribers if payload won't compile
                payload.compile()
            catch e
                logger.error "Invalid payload, template doesn't compile"
                cb(-1) if cb
                return

            logger.verbose "Pushing message for userID #{event.name}"
            logger.silly "data = #{JSON.stringify data}"
            logger.silly 'Title: ' + payload.localizedTitle('en')
            logger.silly payload.localizedMessage('en')

            protoCounts = {}
            event.forEachSubscribers (subscriber, subOptions, done) =>
                # action
                subscriber.get (info) =>
                    if info?.proto?
                        if protoCounts[info.proto]?
                            protoCounts[info.proto] += 1
                        else
                            protoCounts[info.proto] = 1

                try
                    logger.verbose "Going to send message to userID #{event.name} and subscriber #{JSON.stringify subscriber.id}"
                    @pushServices.push(subscriber, subOptions, payload, done)
                catch error
                  logger.error 'ERROR from push driver'
                  logger.error 'Protocol'
                  logger.error protoCounts
                  logger.error error
            , (totalSubscribers) =>
                # finished
                logger.verbose "Pushed to #{totalSubscribers} subscribers"
                for proto, count of protoCounts
                    logger.verbose "#{count} #{proto} subscribers"

                if totalSubscribers > 0
                    # update some event' stats
                    event.log =>
                        cb(totalSubscribers) if cb
                else
                    # if there is no subscriber, cleanup the event
                    event.delete =>
                        cb(0) if cb
exports.EventPublisher = EventPublisher

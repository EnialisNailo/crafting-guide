###
Crafting Guide - craft_page_controller.coffee

Copyright (c) 2014-2015 by Redwood Labs
All rights reserved.
###

AdsenseController   = require './adsense_controller'
CraftPage           = require '../models/craft_page'
InventoryController = require './inventory_controller'
PageController      = require './page_controller'
StepController      = require './step_controller'
_                   = require 'underscore'
{Event}             = require '../constants'
{Text}              = require '../constants'
{Url}               = require '../constants'

########################################################################################################################

module.exports = class CraftPageController extends PageController

    constructor: (options={})->
        if not options.imageLoader? then throw new Error 'options.imageLoader is required'
        if not options.modPack? then throw new Error 'options.modPack is required'
        if not options.storage? then throw new Error 'options.storage is required'

        options.model ?= new CraftPage modPack:options.modPack
        options.templateName = 'craft_page'
        super options

        @imageLoader = options.imageLoader
        @modPack     = options.modPack
        @storage     = options.storage

        @model.craftsman.on Event.change, => @tryRefresh()

    # Event Methods ################################################################################

    onHaveInventoryChanged: ->
        @storage.store 'crafting-plan:have', @model.craftsman.have.unparse()

    onMoveNeedToHave: (itemSlug)->
        quantity = @model.craftsman.need.quantityOf itemSlug
        @model.craftsman.have.add itemSlug, quantity
        @onHaveInventoryChanged()

    onRemoveFromHaveInventory: (itemSlug)->
        @model.craftsman.have.remove itemSlug
        @onHaveInventoryChanged()

    onRemoveFromWant: (itemSlug)->
        @model.craftsman.want.remove itemSlug
        @onWantInventoryChange()

    onStepComplete: (stepController)->
        step = stepController.model
        for stack in step.recipe.output
            @model.craftsman.have.add stack.itemSlug, stack.quantity * step.multiplier
        @onHaveInventoryChanged()

    onWantInventoryChange: ->
        text = @model.craftsman.want.unparse()
        url = Url.crafting inventoryText:text
        router.navigate url

        if @model.craftsman.want.isEmpty
            @model.craftsman.have.clear()
            @onHaveInventoryChanged()

    # PageController Overrides #####################################################################

    getMetaDescription: ->
        return Text.craftDescription()

    getTitle: ->
        return 'Craft'

    # BaseController Overrides #####################################################################

    onDidRender: ->
        @adsenseController = @addChild AdsenseController, '.view__adsense', model:'sidebar_skyscraper'

        @wantInventoryController = @addChild InventoryController, '.want .view__inventory',
            imageLoader:     @imageLoader
            isAcceptable:    (item)=> item.isCraftable
            model:           @model.craftsman.want
            modPack:         @modPack
            firstButtonType: 'remove'
        @wantInventoryController.on Event.button.first, (c, s)=> @onRemoveFromWant(s)
        @wantInventoryController.on Event.change, (c)=> @onWantInventoryChange()

        @haveInventoryController = @addChild InventoryController, '.have .view__inventory',
            imageLoader:     @imageLoader
            model:           @model.craftsman.have
            modPack:         @modPack
            firstButtonType: 'down'
        @haveInventoryController.on Event.button.first, (c, s)=>
            @onRemoveFromHaveInventory(s)
        @haveInventoryController.on Event.change, (c)=> @onHaveInventoryChanged()

        @needInventoryController = @addChild InventoryController, '.need .view__inventory',
            editable:        false
            imageLoader:     @imageLoader
            model:           null
            modPack:         @modPack
            firstButtonType: 'up'
        @needInventoryController.on Event.button.first, (c, s)=> @onMoveNeedToHave(s)

        @$instructionsSection = @$('.instructions.section')
        @$makeSection         = @$('.make.section')
        @$toolsSection        = @$('.tools.section')
        @$ingredientsSection  = @$('.ingredients.section')
        @$stepsSection        = @$('.steps.section')
        @$stepsContainer      = @$('.steps.section .panel')

        super

    onWillRender: ->
        @model.craftsman.have.clear()
        @model.craftsman.have.parse @storage.load('crafting-plan:have')
        super

    refresh: ->
        @needInventoryController.model = @model.craftsman.plan?.need
        @_refreshSectionVisibility()
        @_refreshSteps()
        @adsenseController.fillAdPositions()
        super

    # Backbone.View Overrides ########################################################################

    events: ->
        return _.extend super,
            'click .instructions a': 'routeLinkClick'

    # Private Methods ################################################################################

    _isStepCompletable: (controller)->
        return not @model.craftsman.want.hasAtLeast controller.model.outputItemSlug

    _refreshSectionVisibility: ->
        if @model.craftsman.want.isEmpty
            for $el in [@$toolsSection, @$ingredientsSection, @$stepsSection]
                @hide $el
            @show @$instructionsSection
        else
            for $el in [@$toolsSection, @$ingredientsSection, @$stepsSection]
                @show $el
            @hide @$instructionsSection

    _refreshSteps: ->
        steps = @model.craftsman.plan?.steps or []
        @_stepControllers ?= []
        index = 0

        for step in steps
            controller = @_stepControllers[index]
            if not controller?
                controller = new StepController
                    canComplete: (controller)=> @_isStepCompletable(controller)
                    imageLoader: @imageLoader
                    model:       step
                    modPack:     @modPack
                controller.on Event.button.complete, (c)=> @onStepComplete(c)
                controller.render()

                @$stepsContainer.append controller.$el
                @_stepControllers.push controller
            else
                controller.model = step

            index += 1

        while @_stepControllers.length > index
            @_stepControllers.pop().remove()

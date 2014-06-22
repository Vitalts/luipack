/*global define*/

define([
    'jquery',
    'underscore',
    'backbone',
    'text!templates/patientedit.html',
    'stickitform'
], function ($, _, Backbone, html, StickitForm) {
    'use strict';

    var PatienteditView = Backbone.View.extend({
      html: html,
      initialize:function(){


      },
      bindings: function(){
        var bindings = StickitForm.getBindings({
          /**
           * Required. List the model attributes to bind here.
           */
          attributes: ['registry', 'name', 'gender', 'birthdate'],
          /**
           * Optional. If attributes require extra stickit options, these will extend generated bindings.
           */
          extend: {
            'country': {
              selectOptions: {
                collection: ['Norway', 'Sweden', 'Denmark', 'Finland', 'Iceland']
              },
              setOptions: {
                validate: false,
                silent: true
              }
            },
            'age': {
              events: ['change'],
              onSet: function(val) {
                return parseInt(val, 10) || undefined;
              }
            }
          }
        });

        return bindings;
      },
      render: function () {
        var title = (this.model.isNew()) ? 'Adicionar': 'Editar';
        title += ' Paciente';
        this.$el.html(this.html);
        this.$('.title-el').html(title);
        this.stickit();
        return this;
      },
      events:{
        'click button.save-model':'saveModel',
        'click button.cancel':'cancel'
      },
      cancel: function () {
        app.mainRouter.navigate('#patients', {trigger:true});
      },
      saveModel: function(){
        var self = this;
        if (this.model.isNew()){
          this.model.collection = this.collection;
          this.model.save({}, {
            success: function(){
              console.log('Paciente salvo');
              self.collection.add(self.model);
              app.mainRouter.navigate('#patients', {trigger: true});
            },
            error: function(model, response, options) {
                console.log('Erro ao salvar os dados: ', response, options);
            }
          });

        } else {
          this.model.save({}, {
            success: function(){
              console.log('Paciente salvo');
              app.mainRouter.navigate('#patients', {trigger: true});
            },
            error: function(model, response, options) {
               console.log('Erro ao salvar os dados: ', response, options);
              }
          });
        }
      }
    });

    return PatienteditView;
});
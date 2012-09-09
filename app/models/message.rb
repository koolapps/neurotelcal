# -*- coding: utf-8 -*-
class Message < ActiveRecord::Base
  attr_accessible :group_id, :description, :name, :processed, :call, :entered, :listened, :anonymous, :call_end, :retries, :hangup_on_ring, :time_limit
  validates :name, :description, :call, :presence => true
  validates :name, :uniqueness => true

  validate :validate_description_call_language

  belongs_to :group
  has_many :message_calendar, :dependent => :destroy


  def validate_description_line(line)
    verbs = ['Reproducir', 
             'ReproducirLocal',
             'Decir',
             'Registrar',
             'Si', #toma el resultado de lo ultimo evaluado
             'Colgar'
            ]

    words = line.split
    verb = words[0]
    arg = words[1..-1].join(' ')
    unless verbs.include? verb
      errors.add(:description, "Solo verbos %s" % verbs.join(','))
      return false
    end
    
    case verb
      #Si se indica reproducir se verifica
      #que si exista un recurso audio con el nombre
      #indicado.
    when 'Reproducir'
      resource = Resource.where(:campaign_id => group.campaign.id, :type_file => 'audio', :name => arg).first
      if resource.nil?
        errors.add(:description, 'Recurso [%s] para reproducir no encontrado.' % arg);
      end
    when 'ReproducirLocal'
      #no se evalua ya que estos archivo estan en el servidor freeswitch
    when 'Registrar'
      register = arg.split[0]
      if register == 'digitos'
      elsif register == 'voz'
      end
    when 'Si'

      begin
        def validar_si_exp(exp)
          condiciones = ["=", ">=", "<="]
          exp.strip.scan(/ *(=) *([^\/]+)(.+)$/) do |condicion, valor, subexp|
            subexp[0]  = ''; subexp.strip!; 

            errors.add(:description, 'Condicion invalida solo =' ) unless condiciones.include?(condicion)
            errors.add(:description, 'Invalida sub expresion de Si') if subexp.empty?
            
            errors.add(:description, 'Falta separador de si y no |') unless subexp.include? '|'
            subsexp = subexp.split('|')
            noexp = subexp.slice(subexp.length - subexp.reverse.index('|'), subexp.length)
            siexp = subexp.slice(0, subexp.length - subexp.reverse.index('|') -1)

            siexp.split('>').each do |sexp|
              if sexp.include?('Si')
                validar_si_exp(sexp)
              else
                validate_description_line(sexp)
              end
            end
            #SI
            noexp.split('>').each do |sexp|
              if sexp.include?('Si')
                validar_si_exp(sexp)
              else
                validate_description_line(sexp)
              end
            end
          end
        end
        validar_si_exp(arg)
      rescue Exception => e
        errors.add(:description, e.message)
      end
    end
  end
  #Validación del lenguaje para llamadas
  #es muy sencillo se tiene los 2 verbos: Reproducir, Decir
  #Reproducir busca un recurso con el nombre indicado y reproduce
  #Decir intenta usar un sistema de voz para decir lo pasado
  #y variables de tipo
  # $... para valor de campo en tabla cliente. Ej: $nombre
  # <%= %> para ejecutar ruby exp
  #@todo validar lo anterior
  def validate_description_call_language
   

    if not description.nil?

      lines = description.split("\n")
      
      lines.each do |line|
        validate_description_line(line)
      end

    end
  end


  def description_line_to_call_sequence(line, replaces)
    words = line.gsub(/ +/," ").split
    verb = words[0]
    arg = words[1..-1].join(' ')
    
    case verb
    when 'Si'
      def evaluar_si_exp(exp, replaces)
        condiciones = ["=", ">=", "<="]
        sequencesi = {}
        exp.strip.scan(/ *(=) *([^\/]+)(.+)$/) do |condicion, valor, subexp|
          subexp[0]  = ''; subexp.strip!; 
          sequencesi[:si] = {:condicion => condicion, :valor => valor.strip!}
          sequencesi[:sicontinuar] = [] unless sequencesi[:sicontinuar].is_a? Array
          sequencesi[:nocontinuar] = [] unless sequencesi[:nocontinuar].is_a? Array
          subsexp = subexp.split('|')
          noexp = subexp.slice(subexp.length - subexp.reverse.index('|'), subexp.length); noexp.strip!
          siexp = subexp.slice(0, subexp.length - subexp.reverse.index('|')); siexp.slice!(siexp.length-1,1); siexp.strip!

          siexp.split('>').each do |sexp|
            
            if sexp.include?('Si')
              sequencesi[:sicontinuar] << evaluar_si_exp(sexp,  replaces)
            else
              print sexp
              sequencesi[:sicontinuar] << description_line_to_call_sequence(sexp, replaces)
            end
          end

          #SI
          noexp.split('>').each do |sexp|
            if sexp.include?('Si')
              sequencesi[:nocontinuar] << evaluar_si_exp(sexp,  replaces)
            else
              sequencesi[:nocontinuar] << description_line_to_call_sequence(sexp, replaces)
            end
          end
        end
        return sequencesi
      end
      sequencesi = {}
      return evaluar_si_exp(arg, replaces)
      when 'Colgar'
        return {:colgar => true, :segundos => 0}
      when 'ReproducirLocal'
        return {:audio_local => arg}
      when 'Reproducir'
        resource = Resource.where(:campaign_id => group.campaign.id, :type_file => 'audio', :name => arg).first
        return {:audio => resource.file}
      when 'Decir'
        replaces.each do |key, value|
          arg = arg.gsub(key.to_s, value.to_s)
        end
        erb = ERB.new(arg)
        decir_str = erb.result
        logger.debug(decir_str)
        return {:decir => decir_str }
      when 'Registrar'
        register = arg.split[0]
        case register
        when 'digitos'
          options = {:retries => 1, :timeout => 5, :numDigits => 99, :validDigits => '0123456789*#'}
          words = arg.scan(/([0-9a-zA-Z\-_\/\\\.ñÑáéíóúÁÉÍÓÚ]+)=([0-9a-zA-Z\-_\/\\\.ñÑáéíóúÁÉÍÓÚ]+|\'[^\']+)/)
          words.each do |word|
            option = word
            option[1][0] = ""if option[1][0] == "'"
            option[1].strip!
            option[0].strip!
            case option[0]
            when 'intentos'
              options[:retries] = option[1].to_i
            when 'duracion'
              options[:timeout] = option[1].to_i
            when 'cantidad'
              options[:numDigits] = option[1].to_i
            when 'digitosValidos'
              options[:validDigits] = option[1].to_s
            when 'audio'
              options[:audio] = option[1].to_s
            end
          end
          
          logger.debug("Options for get digits " + options.to_s)
          
          return {:register => :digits, :options => options}
        end
      end
  end
  #Parsea :description y retorna arreglo con la secuencia indicada
  #Se tiene las siguientes acciones:
  # * Decir .... usa speak para decir algo, se puede incluir código ruby <%= %> para consultar en otras tablas, o lo que se quiera
  # * Reproducir Reproduce archivo remoto
  # * ReproducirLocal reproudce archivo donde se encuentre el servidor freeswitch
  #@return array
  def description_to_call_sequence(replaces = {})
    return false unless description
    sequence = []

    lines = description.split("\n")
      
    lines.each do |line|
      sequence << description_line_to_call_sequence(line, replaces)
    end    
    return sequence
  end
end

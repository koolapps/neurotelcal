=begin
 PlivoCall es la memoria de trabajo de neurotelcal para la realizacion de llamadas
 es de suma importancia no realizar consultas de este modelo, ya que estos datos pueden
 ser eliminados sin comprometer el funcionamiento del programa. Se van dejando registro
 de las llamadas para que puedan ser copiados o respaldados, en pocas palabras
 viene siendo el CDR de Neurotelcal.
=end
class PlivoCall < ActiveRecord::Base
  ANSWER_ENUMERATION = ['NORMAL_CLEARING'] #lo que se considera respuesta
  REJECTED_ENUMERATION = ['INVALID_NUMBER_FORMAT', 'CHAN_NOT_IMPLEMENTED', 'INCOMPATIBLE_DESTINATION'] #ni modo de llamar
  INVALID_ENUMERATION = ['INVALID_NUMBER_FORMAT'] #ni modo de llamar
  attr_accessible :data, :uuid, :status, :hangup_enumeration, :call_id, :created_at, :plivo_id, :step, :number, :bill_duration, :call, :end, :id, :updated_at
  
  liquid_methods :hangup_enumeration, :number, :bill_duration, :created_at, :end

  belongs_to :call
  belongs_to :plivo

  def call_sequence
    return YAML::load(data)
  end
  
  def update_call_sequence(seq)
    self.data = seq.to_yaml
    self.save()
  end
  
  def reset_step
    self.step = 0
    self.save()
  end

  def next_step
    self.step += 1
    self.save()
  end

  def answered?
    answer_list = PlivoCall::ANSWER_ENUMERATION
    return answer_list.include?(self.hangup_enumeration)
  end
  
  def self.answered?(cause)
    answer_list = PlivoCall::ANSWER_ENUMERATION
    return answer_list.include?(cause)
  end
  
 

end

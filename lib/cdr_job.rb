# Copyright (C) 2012 Bit4Bit <bit4bit@riseup.net>
#
#
# This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.


class CDRJob < Struct.new(:file, :user_id, :campaign_id, :group_id)


  def perform
    extension = nil
    file = nil
    

    case self.file
    when Hash
      extension = self.file[:ext]
      file = self.file[:path]
    when String
      extension = File.extname(self.file)
      file = self.file
    end
    

    case extension
    when ".db"
    when ".sqlite3"
      import_from_sqlite(file, self.user_id)
    when ".csv"
      import_from_plain(file, self.user_id, self.campaign_id, self.group_id)
    else
      Notification.new({:user_id => self.user_id,
                         :msg => "Extension invalida del archivo a importar cdr. Si es sqlite poner extension .db,.sqlite3, Si es CSV poner extension .csv. Se recibio" + extension,
                         :type_msg => 'notice'}).save(:validate => false)
    end

  end

  private
  def import_from_plain(file, user_id, campaign_id, group_id)
    raise 'import_from_plain not implement csv cdr upload'
  end
  
  def import_from_sqlite(file, user_id)
    CdrSqlite.establish_connection(:adapter => 'sqlite3', :database => file)
    total_imported = 0
    
    total = CdrSqlite.count
    Notification.new({:user_id => user_id,
                       :msg => 'Importando CDR con un total de %d registros.' % total,
                       :type_msg => 'notice'}).save(:validate => false)
    Cdr.transaction do
      CdrSqlite.all.each do |cdrFS|
        next if Cdr.where(:uuid => cdrFS.uuid).exists?
        next unless PlivoCall.where(:uuid => cdrFS.uuid).exists?
        cdr = Cdr.new(:caller_id_name => cdrFS.caller_id_name,
                      :caller_id_number =>  cdrFS.caller_id_number,
                      :destination_number => cdrFS.destination_number,
                      :context => cdrFS.context,
                      :start_stamp => cdrFS.start_stamp,
                      :answer_stamp => cdrFS.answer_stamp,
                      :end_stamp => cdrFS.end_stamp,
                      :duration => cdrFS.duration,
                      :billsec => cdrFS.billsec,
                      :hangup_cause => cdrFS.hangup_cause,
                      :uuid => cdrFS.uuid,
                      :bleg_uuid => cdrFS.bleg_uuid,
                      :account_code => cdrFS.account_code
                      )
        cdr.save()
        total_imported += 1
        percent = ((total_imported * 100) / total)
        if ( percent % 20 == 0 or percent % 40 == 0 or percent % 80 == 0)
          Notification.new({:user_id => user_id,
                             :msg => 'Porcentaje %d hasta ahora importado de %d registros.' % [((total_imported * 100) / total), total_imported],
                             :type_msg => 'notice'}).save(:validate => false)
        end
        
      end
    end
    Notification.new({:user_id => user_id,
                       :msg => 'Finalizada importacion CDR con un total de %d registros.' % total_imported,
                       :type_msg => 'notice'}).save(:validate => false)
  end
  
end

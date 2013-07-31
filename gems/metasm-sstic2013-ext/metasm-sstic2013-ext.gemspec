Gem::Specification.new do |s|
  s.name        = "metasm-sstic2013-ext"
  s.version     = "0.0.1"
  s.date        = "2013-05-06"
  s.summary     = "Extension Metasm pour gérer le FPGA du challenge Sstic 2013"
  s.description =<<EOS
Extension Metasm pour gérer le FPGA du challenge Sstic 2013
EOS
  s.authors     = [ "Julien Perrot" ]
  s.email       = "perrot@gmail.com"
  s.executables << "disas-sstic2013"
  s.files        = Dir["lib/**/*.rb"]
  s.homepage     = "http://communaute.sstic.org/ChallengeSSTIC2013"
end

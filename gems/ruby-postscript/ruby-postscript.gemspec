Gem::Specification.new do |s|
  s.name        = "ruby-postscript"
  s.version     = "0.0.1"
  s.date        = "2013-05-06"
  s.summary     = "Postscript interpreter / debugger implemented in Ruby"
  s.description =<<EOS
Interpréteur Postscript simpliste développé dans le cadre de
la résolution du challenge SSTIC 2013
EOS
  s.authors     = [ "Julien Perrot" ]
  s.email       = "perrot@gmail.com"
  s.executables << "ruby-ps"
  s.files        = Dir["lib/**/*.rb"]
  s.homepage     = "http://communaute.sstic.org/ChallengeSSTIC2013"
  s.add_dependency "awesome_print", ">=1.1.0"
end

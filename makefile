.default: test

test: 
	ruby test.rb
	
install:
	install -d /usr/local/bin
	chmod +x dtrain.rb
	install dtrain.rb /usr/local/bin/dtrain

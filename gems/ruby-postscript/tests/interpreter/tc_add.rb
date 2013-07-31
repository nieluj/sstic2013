require 'postscript/interpreter'
require 'test/unit'

class TestAdd < Test::Unit::TestCase

  def setup
    @postscript = Postscript::Interpreter.new
  end

  def test_not_enough_args
    assert_raise ( Postscript::StackUnderflowError) { @postscript.execute [ :add ]  }
    assert_raise ( Postscript::StackUnderflowError) { @postscript.execute [ 1, :add ] }
  end

  def test_do_add
    @postscript.execute [ 1, 2, :add ]
    assert_equal( [ 3 ], @postscript.stack )
    @postscript.execute [ 5, :add ]
    assert_equal( [ 8 ], @postscript.stack )
    @postscript.execute "2 add"
    assert_equal( [ 10 ], @postscript.stack )

    @postscript.reset
    @postscript.execute "1 2 add 3 add 4 add"
    assert_equal( [ 10 ], @postscript.stack )
  end

end

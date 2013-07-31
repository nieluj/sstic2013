require 'postscript/interpreter'
require 'test/unit'

class TestExch < Test::Unit::TestCase

  def setup
    @postscript = Postscript::Interpreter.new
  end

  def test_not_enough_args
    assert_raise ( Postscript::StackUnderflowError) { @postscript.execute [ :exch ]  }
    @postscript.reset
    assert_raise ( Postscript::StackUnderflowError) { @postscript.execute [ 1, :exch ] }
  end

  def test_do_exch
    @postscript.reset
    @postscript.execute [ 1, 2, :exch ]
    assert_equal( [ 2, 1 ], @postscript.stack )

    @postscript.reset
    @postscript.execute "1 2 3 exch"
    assert_equal( [ 1, 3, 2 ], @postscript.stack )
  end

end

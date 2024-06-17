// import lol from `util`
// lol()
import './panorama_adapter'
import * as React from 'react'
import { render } from 'react-panorama'

abstract class Lib {
	
	abstract name: string
}

class Basis extends Lib {

	name = 'basis'
}

// ----------------------------------------------------------------------------------------------

const basis = new Basis()



// -----------------------------------------------


// (GameUI.CustomUIConfig() as any).basis = new Basis()